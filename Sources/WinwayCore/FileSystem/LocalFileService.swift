import Foundation
import Darwin
import CryptoKit

/// Blocking filesystem work is isolated on dedicated queues, never MainActor.
public final class LocalFileService: FileServing, @unchecked Sendable {
    private let reads = DispatchQueue(label: "app.winway.files.read", qos: .userInitiated)
    private let searches = DispatchQueue(label: "app.winway.files.search", qos: .userInitiated)
    private let writes = DispatchQueue(label: "app.winway.files.write", qos: .userInitiated)
    private let jobsLock = NSLock()
    private var submittedJobs: Set<UUID> = []
    private let searchClient: FSearchClient
    public init() { searchClient = FSearchClient() }
    init(searchClient: FSearchClient) { self.searchClient = searchClient }

    public static func resolvePath(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    public func listDirectory(_ directory: URL, includeHidden: Bool = false) async throws -> [FileEntry] {
        try await perform(on: reads, context: directory) {
            let fm = FileManager.default
            let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isHiddenKey], options: [])
            return try urls.compactMap { url in
                let entry = try self.readEntry(url)
                return includeHidden || !entry.isHidden ? entry : nil
            }
        }
    }

    public func searchDirectory(_ directory: URL, query: String, includeHidden: Bool = false,
                                cancellation: FileOperationCancellation = .init()) async throws -> FileSearchResult {
        try await withTaskCancellationHandler {
            try await perform(on: searches, context: directory) {
                func checkCancellation() throws {
                    if cancellation.isCancelled { throw FileServiceError(.cancelled, "搜索已取消") }
                }
                try checkCancellation()
                guard !query.isEmpty else { return FileSearchResult(entries: [], skippedCount: 0) }
                let root = directory.resolvingSymlinksInPath().standardizedFileURL
                guard (try self.statFollowing(root).st_mode & S_IFMT) == S_IFDIR else {
                    throw FileServiceError(.notFound, "搜索目录不存在。", path: directory.path)
                }
                guard FileManager.default.isReadableFile(atPath: root.path) else {
                    throw FileServiceError(.permissionDenied, "没有权限搜索此目录。", path: directory.path)
                }
                let response = try self.searchClient.search(directory: root, query: query, cancellation: cancellation)
                let hits = response.hits ?? response.files ?? []
                let prefix = root.path == "/" ? "/" : root.path + "/"
                var matches: [FileEntry] = []
                var skipped = 0
                var seen = Set<String>()
                // Cache ancestor checks: many hits share the same containing folders.
                var allowedFolders: [URL: Bool] = [root: true]
                func allowed(_ folder: URL) throws -> Bool {
                    try checkCancellation()
                    if let value = allowedFolders[folder] { return value }
                    guard folder.path.hasPrefix(prefix) else { return false }
                    let entry = try self.readEntry(folder)
                    let value = try entry.isDirectory && !entry.isSymbolicLink && (includeHidden || !entry.isHidden)
                        && allowed(folder.deletingLastPathComponent())
                    allowedFolders[folder] = value
                    return value
                }
                for hit in hits.prefix(FSearchClient.resultLimit) {
                    try checkCancellation()
                    let url = URL(fileURLWithPath: hit.path).standardizedFileURL
                    // Defense in depth: never show a hit outside the requested directory.
                    guard url.path.hasPrefix(prefix), url != root, seen.insert(url.path).inserted else { continue }
                    do {
                        guard try allowed(url.deletingLastPathComponent()) else { continue }
                        let entry = try self.readEntry(url)
                        guard includeHidden || !entry.isHidden else { continue }
                        // Keep the navigation path when the search root itself is a symlink.
                        let displayed = directory.appendingPathComponent(String(url.path.dropFirst(prefix.count)))
                        matches.append(FileEntry(url: displayed, name: entry.name, isDirectory: entry.isDirectory,
                            isSymbolicLink: entry.isSymbolicLink, size: entry.size, modified: entry.modified,
                            kind: entry.kind, isHidden: entry.isHidden))
                    } catch {
                        try checkCancellation()
                        skipped += 1
                    }
                }
                try checkCancellation()
                return FileSearchResult(entries: matches, skippedCount: skipped,
                    isTruncated: hits.count > FSearchClient.resultLimit,
                    isIndexing: (response.indexing ?? 0) > 0 || response.complete == false, limitedAccess: response.limitedAccess)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func readEntry(_ url: URL) throws -> FileEntry {
        let info = try statLink(url)
        let link = (info.st_mode & S_IFMT) == S_IFLNK
        let directory = (info.st_mode & S_IFMT) == S_IFDIR
        let hidden = url.lastPathComponent.hasPrefix(".") || ((try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false)
        let kind = link ? "符号链接" : directory ? "文件夹" : url.pathExtension.isEmpty ? "文件" : "\(url.pathExtension.uppercased()) 文件"
        return FileEntry(url: url, name: url.lastPathComponent, isDirectory: directory, isSymbolicLink: link,
                         size: info.st_size, modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9), kind: kind, isHidden: hidden)
    }

    public func createDirectory(in directory: URL, name: String) async throws -> URL {
        try await perform(on: writes, context: directory) {
            try self.validateName(name)
            let target = directory.appendingPathComponent(name)
            guard try !self.nameOccupied(target) else { throw self.conflict(target) }
            guard mkdir(target.path, 0o755) == 0 else { throw self.posixError(target) }
            return target
        }
    }

    public func rename(_ source: URL, to name: String) async throws -> URL {
        try await perform(on: writes, context: source) {
            try self.validateName(name)
            let sourceInfo = try self.statLink(source)
            let target = source.deletingLastPathComponent().appendingPathComponent(name)
            if source.standardizedFileURL == target.standardizedFileURL { return source }
            if try self.nameOccupied(target) {
                // On a case-insensitive volume the target can resolve to the
                // source itself. RENAME_EXCL permits that spelling change while
                // still refusing a different item created before the syscall.
                let sensitive = try source.deletingLastPathComponent().resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
                let sameSpelling = source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased() == name.precomposedStringWithCanonicalMapping.lowercased()
                guard sensitive == false, sameSpelling,
                      let targetInfo = try? self.statLink(target),
                      sourceInfo.st_dev == targetInfo.st_dev, sourceInfo.st_ino == targetInfo.st_ino else {
                    throw self.conflict(target)
                }
            }
            try self.exclusiveRename(source, target)
            return target
        }
    }

    public func transfer(_ request: FileTransferRequest,
                         cancellation: FileOperationCancellation = FileOperationCancellation(),
                         onProgress: @escaping @Sendable (FileOperationProgress) -> Void = { _ in },
                         resolveConflict: @escaping @Sendable (FileConflict) async -> FileConflictChoice = { _ in .skip }) async -> FileOperationReport {
        let inserted = jobsLock.withLock { submittedJobs.insert(request.id).inserted }
        guard inserted else {
            return FileOperationReport(jobID: request.id, kind: request.kind, results: request.sources.map {
                FileItemResult(source: $0, destination: nil, outcome: .failed,
                               error: FileServiceError(.duplicateJob, "此任务已提交；重试请创建新任务。"), residualURLs: [])
            }, state: .failed)
        }
        onProgress(FileOperationProgress(jobID: request.id, total: request.sources.count, processed: 0, succeeded: 0, failed: 0, currentSource: nil, state: .queued))
        return await withCheckedContinuation { continuation in
            writes.async {
                var results: [FileItemResult] = []
                func progress(_ state: FileOperationState, _ source: URL?) {
                    onProgress(FileOperationProgress(jobID: request.id, total: request.sources.count, processed: results.count,
                        succeeded: results.filter { $0.outcome == .succeeded }.count, failed: results.filter { $0.outcome == .failed }.count,
                        currentSource: source, state: state))
                }
                for source in request.sources {
                    if cancellation.isCancelled {
                        results.append(FileItemResult(source: source, destination: nil, outcome: .cancelled, error: nil, residualURLs: [])); continue
                    }
                    progress(.running, source)
                    var target = request.destination.appendingPathComponent(source.lastPathComponent)
                    do {
                        try self.validateDestination(source, request.destination, kind: request.kind)
                        func nextTarget(afterConflict target: URL) throws -> URL? {
                            progress(.awaitingConflict, source)
                            let choice = self.waitForConflict(FileConflict(source: source, destination: target), cancellation: cancellation, resolve: resolveConflict)
                            switch choice {
                            case .skip: return nil
                            case .cancel: cancellation.cancel(); return nil
                            case .keepBoth:
                                let next = try self.availableName(request.destination.appendingPathComponent(source.lastPathComponent))
                                progress(.running, source)
                                return next
                            }
                        }
                        var shouldSkip = false
                        // Exclusive rename remains the final authority if another process creates a target after this check.
                        while try self.nameOccupied(target) {
                            guard let next = try nextTarget(afterConflict: target) else {
                                shouldSkip = !cancellation.isCancelled
                                break
                            }
                            target = next
                            if cancellation.isCancelled { break }
                        }
                        if shouldSkip || cancellation.isCancelled {
                            results.append(FileItemResult(source: source, destination: nil, outcome: shouldSkip ? .skipped : .cancelled, error: nil, residualURLs: []))
                        } else {
                            progress(.running, source)
                            results.append(self.transferItem(source, target, kind: request.kind, cancellation: cancellation,
                                                             resolveConflict: nextTarget(afterConflict:)))
                        }
                    } catch {
                        results.append(FileItemResult(source: source, destination: nil, outcome: .failed, error: self.map(error, source), residualURLs: []))
                    }
                    progress(.running, nil)
                }
                let failures = results.filter { $0.outcome == .failed }.count
                let successes = results.filter { $0.outcome == .succeeded }.count
                let state: FileOperationState = cancellation.isCancelled ? .cancelled : failures > 0 ? (successes > 0 ? .partial : .failed) : .completed
                progress(state, nil)
                continuation.resume(returning: FileOperationReport(jobID: request.id, kind: request.kind, results: results, state: state))
            }
        }
    }

    private func transferItem(_ source: URL, _ initialTarget: URL, kind: FileTransferKind,
                              cancellation: FileOperationCancellation,
                              resolveConflict: (URL) throws -> URL?) -> FileItemResult {
        let fm = FileManager.default
        var target = initialTarget
        var temporary: URL?
        var committed = false
        var quarantine: URL?
        func skippedResult() -> FileItemResult {
            FileItemResult(source: source, destination: nil,
                           outcome: cancellation.isCancelled ? .cancelled : .skipped, error: nil, residualURLs: [])
        }
        do {
            let sourceInfo = try statLink(source)
            let targetDirectoryInfo = try statFollowing(target.deletingLastPathComponent())
            if kind == .move && sourceInfo.st_dev == targetDirectoryInfo.st_dev {
                guard try commit(source, to: &target, cancellation: cancellation, resolveConflict: resolveConflict) else { return skippedResult() }
            } else {
                // Only a cross-volume move needs verification before deleting its source.
                let before = kind == .move ? try snapshot(source) : nil
                let staging = target.deletingLastPathComponent().appendingPathComponent(".winway-copy-\(UUID().uuidString)")
                temporary = staging
                try fm.copyItem(at: source, to: staging)
                if let before {
                    let copied = try snapshot(staging)
                    guard before == (try snapshot(source)) else { throw FileServiceError(.sourceChanged, "复制期间源项目发生变化；未删除源项目。", path: source.path) }
                    guard before.matchesCopy(copied) else { throw FileServiceError(.io, "副本内容或元数据校验不一致；源文件已保留。", path: source.path) }
                }
                guard try commit(staging, to: &target, cancellation: cancellation, resolveConflict: resolveConflict) else {
                    try fm.removeItem(at: staging)
                    temporary = nil
                    return skippedResult()
                }
                temporary = nil; committed = true
                if let before {
                    // Atomically claim the same directory entry before deleting; an externally replaced source is never removed.
                    let held = source.deletingLastPathComponent().appendingPathComponent(".winway-move-\(UUID().uuidString)")
                    try exclusiveRename(source, held)
                    quarantine = held
                    let heldSnapshot = try snapshot(held)
                    guard before.content == heldSnapshot.content && before.identities == heldSnapshot.identities else {
                        throw FileServiceError(.sourceChanged, "移动期间源项目发生变化；目标副本已保留，源项目未删除。", path: source.path)
                    }
                    try fm.removeItem(at: held)
                    quarantine = nil
                }
            }
            return FileItemResult(source: source, destination: target, outcome: .succeeded, error: nil, residualURLs: [])
        } catch {
            var residuals: [URL] = committed ? [target] : []
            var mapped = map(error, source)
            if let quarantine {
                do { try exclusiveRename(quarantine, source) }
                catch { residuals.append(quarantine); mapped = FileServiceError(mapped.code, "\(mapped.message) 原位置恢复失败，源保留于 \(quarantine.path)。", path: source.path) }
            }
            if let temporary, exists(temporary) {
                do { try fm.removeItem(at: temporary) }
                catch { residuals.append(temporary); mapped = FileServiceError(mapped.code, "\(mapped.message) 临时副本未能清理：\(temporary.path)。", path: source.path) }
            }
            return FileItemResult(source: source, destination: committed ? target : nil,
                                  outcome: mapped.code == .cancelled ? .cancelled : .failed, error: mapped, residualURLs: residuals)
        }
    }

    /// Keep the prepared copy while resolving late conflicts; retry only the rename.
    private func commit(_ prepared: URL, to target: inout URL, cancellation: FileOperationCancellation,
                        resolveConflict: (URL) throws -> URL?) throws -> Bool {
        while true {
            if cancellation.isCancelled { throw FileServiceError(.cancelled, "任务已取消，源项目保持不变。") }
            do {
                guard try !nameOccupied(target) else { throw conflict(target) }
                try exclusiveRename(prepared, target)
                return true
            } catch {
                guard (error as? FileServiceError)?.code == .conflict else { throw error }
                guard let next = try resolveConflict(target) else { return false }
                target = next
            }
        }
    }

    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileServiceError(.invalidName, "名称不能为空、.、..，也不能包含 / 或空字符。")
        }
    }

    private func validateDestination(_ source: URL, _ directory: URL, kind: FileTransferKind) throws {
        let info = try statLink(source)
        let destination = try statFollowing(directory)
        guard (destination.st_mode & S_IFMT) == S_IFDIR else { throw FileServiceError(.invalidDestination, "目标不是文件夹。", path: directory.path) }
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let descendantPrefix = resolvedSource == "/" ? "/" : resolvedSource + "/"
        if (info.st_mode & S_IFMT) == S_IFDIR && (resolvedDirectory == resolvedSource || resolvedDirectory.hasPrefix(descendantPrefix)) {
            throw FileServiceError(.invalidDestination, "不能将文件夹复制或移动到自身或子目录。", path: directory.path)
        }
        if kind == .move && source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL {
            throw FileServiceError(.invalidDestination, "项目已经位于此文件夹。", path: source.path)
        }
    }

    private func availableName(_ target: URL) throws -> URL {
        let ext = target.pathExtension
        let stem = ext.isEmpty ? target.lastPathComponent : target.deletingPathExtension().lastPathComponent
        for number in 2...100_000 {
            let candidate = target.deletingLastPathComponent().appendingPathComponent("\(stem) (\(number))\(ext.isEmpty ? "" : "." + ext)")
            if try !nameOccupied(candidate) { return candidate }
        }
        throw FileServiceError(.conflict, "无法生成未占用的名称。", path: target.path)
    }

    private func nameOccupied(_ target: URL) throws -> Bool {
        if exists(target) { return true }
        let parent = target.deletingLastPathComponent()
        let sensitive = (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) ?? false
        func normalized(_ name: String) -> String {
            let canonical = name.precomposedStringWithCanonicalMapping
            return sensitive ? canonical : canonical.lowercased()
        }
        let name = normalized(target.lastPathComponent)
        return try FileManager.default.contentsOfDirectory(atPath: parent.path).contains { normalized($0) == name }
    }

    private func exclusiveRename(_ source: URL, _ destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw posixError(destination) }
    }
    private func exists(_ url: URL) -> Bool { var value = stat(); return lstat(url.path, &value) == 0 }
    private func statLink(_ url: URL) throws -> stat {
        var value = stat(); guard lstat(url.path, &value) == 0 else { throw posixError(url) }; return value
    }
    private func statFollowing(_ url: URL) throws -> stat {
        var value = stat(); guard stat(url.path, &value) == 0 else { throw posixError(url) }; return value
    }
    private func conflict(_ url: URL) -> FileServiceError { FileServiceError(.conflict, "目标名称已被占用：\(url.lastPathComponent)", path: url.path) }
    private func posixError(_ url: URL) -> FileServiceError {
        let number = errno
        let code: FileServiceError.Code = number == ENOENT || number == ENOTDIR ? .notFound : number == EACCES || number == EPERM ? .permissionDenied : number == EROFS ? .readOnly : number == EEXIST || number == ENOTEMPTY ? .conflict : .io
        return FileServiceError(code, "\(String(cString: strerror(number)))：\(url.path)", path: url.path)
    }
    private func map(_ error: Error, _ url: URL) -> FileServiceError {
        if let error = error as? FileServiceError { return error }
        let error = error as NSError
        let code: FileServiceError.Code
        switch error.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError: code = .notFound
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: code = .permissionDenied
        case NSFileWriteVolumeReadOnlyError: code = .readOnly
        case NSFileWriteFileExistsError: code = .conflict
        default: code = .io
        }
        return FileServiceError(code, "\(error.localizedDescription)（\(url.path)）", path: url.path)
    }
    private func perform<T: Sendable>(on queue: DispatchQueue, context: URL, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: self.map(error, context)) } }
        }
    }

    private final class ConflictBox: @unchecked Sendable {
        let lock = NSLock(); var choice: FileConflictChoice = .cancel
        func set(_ value: FileConflictChoice) { lock.withLock { choice = value } }
        func get() -> FileConflictChoice { lock.withLock { choice } }
    }
    private func waitForConflict(_ conflict: FileConflict, cancellation: FileOperationCancellation,
                                 resolve: @escaping @Sendable (FileConflict) async -> FileConflictChoice) -> FileConflictChoice {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ConflictBox()
        let task = Task { result.set(await resolve(conflict)); semaphore.signal() }
        while semaphore.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if cancellation.isCancelled { task.cancel(); return .cancel }
        }
        return result.get()
    }

    private struct Snapshot: Equatable {
        var content: [String: Content] = [:]
        var identities: [String: String] = [:]
        var changes: [String: String] = [:]

        func matchesCopy(_ copy: Snapshot) -> Bool {
            content.count == copy.content.count && content.allSatisfy { path, original in
                guard let copied = copy.content[path] else { return false }
                return original.matchesCopy(copied)
            }
        }
    }
    struct Content: Equatable {
        let mode: mode_t
        let modified: String
        let digest: String
        let attributes: [String: Data]

        func matchesCopy(_ copy: Content) -> Bool {
            // macOS can assign a new provenance value to the copy. Keep it in the
            // full snapshot so source mutation checks still compare every attribute.
            let originalAttributes = attributes.filter { $0.key != "com.apple.provenance" }
            let copiedAttributes = copy.attributes.filter { $0.key != "com.apple.provenance" }
            return mode == copy.mode && modified == copy.modified && digest == copy.digest
                && originalAttributes == copiedAttributes
        }
    }
    private func snapshot(_ root: URL) throws -> Snapshot {
        var result = Snapshot()
        func visit(_ url: URL, _ relative: String) throws {
            let info = try statLink(url)
            let type = info.st_mode & S_IFMT
            var digest = ""
            if type == S_IFREG {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var hash = SHA256()
                while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
                digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            } else if type == S_IFLNK {
                digest = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            } else if type != S_IFDIR {
                throw FileServiceError(.io, "不支持复制设备、套接字或管道。", path: url.path)
            }
            result.content[relative] = Content(mode: info.st_mode, modified: "\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)", digest: digest, attributes: try extendedAttributes(url))
            result.identities[relative] = "\(info.st_dev):\(info.st_ino)"
            result.changes[relative] = "\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec):\(info.st_size)"
            if type == S_IFDIR {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try visit(child, relative + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(root, "")
        return result
    }

    private func extendedAttributes(_ url: URL) throws -> [String: Data] {
        let length = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        if length < 0 { throw posixError(url) }
        guard length > 0 else { return [:] }
        var buffer = [CChar](repeating: 0, count: length)
        let actual = listxattr(url.path, &buffer, length, XATTR_NOFOLLOW)
        guard actual >= 0 else { throw posixError(url) }
        let names = buffer.prefix(actual).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        var values: [String: Data] = [:]
        for name in names {
            let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { throw posixError(url) }
            var data = Data(count: size)
            let count = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
            guard count >= 0 else { throw posixError(url) }
            data.count = count; values[name] = data
        }
        return values
    }
}
