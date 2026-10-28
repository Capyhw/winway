import Foundation
import Darwin

/// JSON-lines adapter for noahdunnagan/fsearch v0.2.1. Run on the file search queue.
/// The short-lived stdio client shares FSearch's persistent index/daemon.
struct FSearchClient: Sendable {
    static let resultLimit = 10_000
    var executableURL: URL?
    var timeout: TimeInterval = 120
    var lifecycle = FSearchProcessLifecycle.shared

    struct Response: Decodable, Sendable {
        struct Hit: Decodable, Sendable { let path: String }
        let ok: Bool
        let error: String?
        let hits: [Hit]?
        let files: [Hit]?
        let complete: Bool?
        let indexing: Int?
        let fullDiskAccess: Bool?
        let entries: Int?
        let contentPending: Int?
        var limitedAccess = false
        enum CodingKeys: String, CodingKey {
            case ok, error, hits, files, complete, indexing
            case fullDiskAccess = "full_disk_access"
            case entries
            case contentPending = "content_pending"
        }
    }

    func status(cancellation: FileOperationCancellation = .init()) throws -> SearchIndexStatus {
        let response = try exchange(["op": "status"], cancellation: cancellation)
        if !response.ok, let error = response.error, error.hasPrefix("indexing:") {
            return SearchIndexStatus(isBuilding: true, fullDiskAccess: nil, entries: nil, pendingContent: nil)
        }
        guard response.ok else { throw FileServiceError(.io, response.error ?? "无法读取搜索索引状态。") }
        return SearchIndexStatus(isBuilding: false, fullDiskAccess: response.fullDiskAccess,
                                 entries: response.entries, pendingContent: response.contentPending)
    }

    func search(directory: URL, query: String, cancellation: FileOperationCancellation) throws -> Response {
        // Scope is a separate JSON field: spaces/quotes in paths cannot alter the query.
        var response = try exchange(["q": query, "in": directory.path, "limit": Self.resultLimit + 1], cancellation: cancellation)
        guard response.ok else { throw FileServiceError(.io, response.error ?? "FSearch 搜索失败。") }
        guard response.hits != nil || response.files != nil else {
            throw FileServiceError(.io, "FSearch 返回了不支持的结果格式。")
        }
        // v0.2.1 deliberately omits these folders without Full Disk Access. Do not
        // misrepresent a skipped Desktop/Documents/etc. as an empty search result.
        let path = directory.path
        let protected = Self.protectedFolders
        if protected.contains(where: { Self.contains($0, path) || Self.contains(path, $0) }) {
            let status = try exchange(["op": "status"], cancellation: cancellation)
            if !status.ok && status.error?.hasPrefix("indexing:") == true {
                throw FileServiceError(.io, "FSearch 首次索引仍在建立，请稍后刷新重试。")
            }
            if status.fullDiskAccess == false {
                if protected.contains(where: { Self.contains($0, path) }) {
                    throw FileServiceError(.permissionDenied, "FSearch 尚未索引此受保护目录。请为 Winway / FSearch 开启完全磁盘访问权限，并重启搜索服务，详见项目搜索说明。")
                }
                response.limitedAccess = true
            } else if !status.ok {
                throw FileServiceError(.io, status.error ?? "无法获取 FSearch 索引状态。")
            }
        }
        return response
    }

    // Mirrors the pinned upstream engine.rs GATED_IN_HOME list.
    private static var protectedFolders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/Containers",
            "Library/Group Containers", "Library/CloudStorage", "Pictures/Photos Library.photoslibrary",
            "Music/Music", "Movies/TV"].map { home + "/" + $0 } + ["/Volumes"]
    }

    private static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private func exchange(_ fields: [String: Any], cancellation: FileOperationCancellation) throws -> Response {
        let executable = try executableURL ?? Self.findExecutable()
        let request = try JSONSerialization.data(withJSONObject: fields) + Data([10])
        guard request.count <= 16_384 else { throw FileServiceError(.io, "搜索条件过长，请缩短后重试。") }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try checkCancellation(cancellation)
        try lifecycle.start(process, cancellation: cancellation)
        // Query cancellation only disposes of this client. App shutdown also
        // stops the bundled daemon through the shared lifecycle.
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            lifecycle.finish(process)
        }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try input.fileHandleForWriting.write(contentsOf: request)
        try input.fileHandleForWriting.close()
        let descriptor = output.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try checkCancellation(cancellation)
            guard Date() < deadline else {
                throw FileServiceError(.io, "FSearch 响应超时，首次索引可能仍在建立，请稍后刷新重试。")
            }
            var event = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&event, 1, 50)
            if ready < 0 {
                if errno == EINTR { continue }
                throw FileServiceError(.io, "无法读取 FSearch 搜索结果。")
            }
            if ready == 0 { continue }
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else {
                try checkCancellation(cancellation)
                if count < 0 && errno == EINTR { continue }
                throw FileServiceError(.io, "FSearch 意外退出或未返回完整结果，请刷新重试。")
            }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 32 * 1_024 * 1_024 else {
                throw FileServiceError(.io, "搜索结果过大，请缩小搜索范围。")
            }
            if let end = data.firstIndex(of: 10) {
                let response = try JSONDecoder().decode(Response.self, from: data.prefix(upTo: end))
                try checkCancellation(cancellation)
                return response
            }
        }
    }

    private func checkCancellation(_ cancellation: FileOperationCancellation) throws {
        if cancellation.isCancelled { throw FileServiceError(.cancelled, "搜索已取消") }
    }

    private static func findExecutable() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["WINWAY_FSEARCH_PATH"].map { URL(fileURLWithPath: $0) },
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/fsearch"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("fsearch"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/fsearch")
        ]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return url
        }
        throw FileServiceError(.notFound, "未找到 FSearch 搜索程序，请重新安装 Winway；开发环境请运行 scripts/prepare-fsearch.sh 并设置 WINWAY_FSEARCH_PATH。")
    }
}
