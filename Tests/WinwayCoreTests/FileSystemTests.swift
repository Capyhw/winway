import Testing
import Foundation
import Darwin
@testable import WinwayCore

final class FileSystemTests: @unchecked Sendable {
    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("winway-files-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }

    @Test func testListingUsesLinkMetadataAndIncludesBrokenLinks() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("你好", root.appendingPathComponent("中文.txt"))
        try write("hidden", root.appendingPathComponent(".hidden"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("失效链接").path, withDestinationPath: "missing")
        let service = LocalFileService()
        let entries = try await service.listDirectory(root)
        #expect((Set(entries.map(\.name))) == (["中文.txt", "失效链接"]))
        #expect((entries.first { $0.name == "中文.txt" }?.size) == (6))
        #expect(try #require(entries.first { $0.name == "失效链接" }).isSymbolicLink)
        let all = try await service.listDirectory(root, includeHidden: true)
        #expect((all.count) == (3))
        do { _ = try await service.listDirectory(root.appendingPathComponent("missing")); Issue.record("missing directory is not empty") }
        catch { #expect(((error as? FileServiceError)?.code) == (.notFound)) }
    }

    @Test func testSearchFindsMultipleLevelsByNameAndPreservesLocations() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("unmatched/another/level")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let direct = root.appendingPathComponent("Report.txt")
        let nested = deep.appendingPathComponent("report.txt")
        let folder = deep.appendingPathComponent("Report folder")
        try write("direct", direct); try write("nested", nested)
        try write("Report only in file contents", deep.appendingPathComponent("unrelated.txt"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let service = LocalFileService()
        let result = try await service.searchDirectory(root, query: "rEpOrT")
        #expect(Set(result.entries.map { $0.url.standardizedFileURL.path }) == Set([direct.path, nested.path, folder.path]))
        #expect(result.skippedCount == 0)
        #expect(result.entries.first { $0.url.standardizedFileURL == nested.standardizedFileURL }?.location(relativeTo: root) == "unmatched/another/level")
        #expect(result.entries.first { $0.url.standardizedFileURL == direct.standardizedFileURL }?.location(relativeTo: root) == "当前目录")
        let listing = try await service.listDirectory(root)
        #expect(listing.count == 2)
        let empty = try await service.searchDirectory(root, query: "no-match")
        #expect(empty.entries.isEmpty)
    }

    @Test func testSearchHonorsHiddenDirectoriesAndDoesNotFollowLinks() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let external = try fixture(); defer { try? FileManager.default.removeItem(at: external) }
        let hidden = root.appendingPathComponent(".hidden/deep")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try write("hidden", hidden.appendingPathComponent("needle.txt"))
        try write("hidden file", root.appendingPathComponent(".needle"))
        try write("outside", external.appendingPathComponent("needle.txt"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: external.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("cycle").path, withDestinationPath: root.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("needle-link").path, withDestinationPath: "missing")
        let service = LocalFileService()
        let visible = try await service.searchDirectory(root, query: "needle")
        #expect(visible.entries.map(\.name) == ["needle-link"])
        #expect(visible.entries.first?.isSymbolicLink == true)
        let all = try await service.searchDirectory(root, query: "needle", includeHidden: true)
        #expect(Set(all.entries.map(\.name)) == Set(["needle.txt", ".needle", "needle-link"]))
        #expect(all.entries.count == 3)
    }

    @Test func testSearchReportsUnreadableChildrenAndFailsForInvalidRoot() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try write("found", root.appendingPathComponent("needle.txt"))
        try write("inaccessible", locked.appendingPathComponent("needle.txt"))
        #expect(chmod(locked.path, 0o000) == 0)
        defer { _ = chmod(locked.path, 0o700) }
        let service = LocalFileService()
        let result = try await service.searchDirectory(root, query: "needle")
        #expect(result.entries.count == 1)
        #expect(result.skippedCount == 1)
        do {
            _ = try await service.searchDirectory(root.appendingPathComponent("missing"), query: "needle")
            Issue.record("An invalid search root must not look like zero matches")
        } catch { #expect((error as? FileServiceError)?.code == .notFound) }
    }

    @Test func testSearchCancellationDoesNotReturnCompletedResults() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cancellation = FileOperationCancellation(); cancellation.cancel()
        do {
            _ = try await LocalFileService().searchDirectory(root, query: "needle", cancellation: cancellation)
            Issue.record("Cancelled searches must not report success")
        } catch { #expect((error as? FileServiceError)?.code == .cancelled) }
        let task = Task { try await LocalFileService().searchDirectory(root, query: "needle") }
        task.cancel()
        do { _ = try await task.value; Issue.record("Task cancellation must reach the search queue") }
        catch { #expect((error as? FileServiceError)?.code == .cancelled) }
    }

    @Test func testCreateRenameValidationAndNoOverwrite() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        for name in ["", "  ", ".", "..", "a/b", "a\0b"] {
            do { _ = try await service.createDirectory(in: root, name: name); Issue.record("非法名称被接受：\(name)") }
            catch { #expect(((error as? FileServiceError)?.code) == (.invalidName)) }
        }
        let a = try await service.createDirectory(in: root, name: "新建")
        _ = try await service.createDirectory(in: root, name: "已有")
        do { _ = try await service.rename(a, to: "已有"); Issue.record("must refuse collision") }
        catch { #expect(((error as? FileServiceError)?.code) == (.conflict)) }
        let b = try await service.rename(a, to: "改名")
        #expect(FileManager.default.fileExists(atPath: b.path))
        #expect(!(FileManager.default.fileExists(atPath: a.path)))
    }

    @Test func testCaseOnlyRenamePreservesFilesDirectoriesAndBrokenLinks() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let file = root.appendingPathComponent("report.txt")
        try write("unchanged payload", file)
        let renamed = try await service.rename(file, to: "Report.txt")
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "unchanged payload")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.contains("Report.txt"))
        #expect(!names.contains("report.txt"))
        let folder = try await service.createDirectory(in: root, name: "folder")
        try write("nested", folder.appendingPathComponent("child.txt"))
        let renamedFolder = try await service.rename(folder, to: "Folder")
        #expect(try String(contentsOf: renamedFolder.appendingPathComponent("child.txt"), encoding: .utf8) == "nested")
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")
        let renamedLink = try await service.rename(link, to: "Shortcut")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: renamedLink.path) == "missing")
    }

    @Test func testRenameStillRejectsDistinctFilesAndHardLinks() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let other = root.appendingPathComponent("Other.txt")
        let hardLink = root.appendingPathComponent("hard-link.txt")
        try write("source", source); try write("other", other)
        try FileManager.default.linkItem(at: source, to: hardLink)
        let service = LocalFileService()
        for name in ["Other.txt", "hard-link.txt"] {
            do { _ = try await service.rename(source, to: name); Issue.record("must reject distinct directory entry: \(name)") }
            catch { #expect((error as? FileServiceError)?.code == .conflict) }
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "source")
        #expect(try String(contentsOf: other, encoding: .utf8) == "other")
        #expect(try String(contentsOf: hardLink, encoding: .utf8) == "source")
    }

    @Test func testCopyPreservesNestedFilesLinksPermissionsTimeAndXattrs() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let source = try await service.createDirectory(in: root, name: "Example.app")
        let target = try await service.createDirectory(in: root, name: "target")
        let file = source.appendingPathComponent("中文.bin")
        try write("payload", file)
        #expect((chmod(file.path, 0o640)) == (0))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: file.path)
        let value = Data("metadata".utf8)
        #expect((value.withUnsafeBytes { setxattr(file.path, "com.winway.fixture", $0.baseAddress, value.count, 0, 0) }) == (0))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "中文.bin")
        let report = await service.transfer(.init(sources: [source], destination: target, kind: .copy))
        #expect((report.succeeded) == (1) , "\(report.results)")
        let output = target.appendingPathComponent("Example.app/中文.bin")
        #expect((try Data(contentsOf: output)) == (Data("payload".utf8)))
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        #expect(((attributes[.posixPermissions] as? NSNumber)?.intValue) == (0o640))
        #expect((attributes[.modificationDate] as? Date) == (Date(timeIntervalSince1970: 1_600_000_000)))
        var data = Data(count: value.count)
        #expect((data.withUnsafeMutableBytes { getxattr(output.path, "com.winway.fixture", $0.baseAddress, value.count, 0, 0) }) == (value.count))
        #expect((data) == (value))
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("Example.app/link").path)) == ("中文.bin"))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func testCopyComparisonOnlyAllowsSystemProvenanceChanges() async throws {
        let metadata = Data("metadata".utf8)
        let originalAttributes = ["com.apple.provenance": Data([1]), "com.winway.fixture": metadata]
        let copiedAttributes = ["com.apple.provenance": Data([2]), "com.winway.fixture": metadata]
        let original = LocalFileService.Content(mode: 0o100640, modified: "123.456", digest: "payload", attributes: originalAttributes)
        let copy = LocalFileService.Content(mode: original.mode, modified: original.modified, digest: original.digest, attributes: copiedAttributes)
        #expect(original.matchesCopy(copy))
        #expect(original != copy) // Source mutation checks must remain strict.

        let withoutProvenance = LocalFileService.Content(mode: original.mode, modified: original.modified, digest: original.digest, attributes: ["com.winway.fixture": metadata])
        #expect(original.matchesCopy(withoutProvenance))
        #expect(withoutProvenance.matchesCopy(original))
        for changed in [
            LocalFileService.Content(mode: 0o100600, modified: original.modified, digest: original.digest, attributes: copiedAttributes),
            LocalFileService.Content(mode: original.mode, modified: "124.456", digest: original.digest, attributes: copiedAttributes),
            LocalFileService.Content(mode: original.mode, modified: original.modified, digest: "corrupt", attributes: copiedAttributes),
            LocalFileService.Content(mode: original.mode, modified: original.modified, digest: original.digest, attributes: [:]),
            LocalFileService.Content(mode: original.mode, modified: original.modified, digest: original.digest, attributes: ["com.winway.fixture": Data("changed".utf8)]),
            LocalFileService.Content(mode: original.mode, modified: original.modified, digest: original.digest, attributes: copiedAttributes.merging(["com.apple.quarantine": Data([1])]) { _, new in new })
        ] {
            #expect(!original.matchesCopy(changed))
        }
    }

    @Test func testSameDirectoryKeepBothWithSystemProvenance() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let file = root.appendingPathComponent("memory-guide.html")
        try write("<html>payload</html>", file)
        let provenance = Data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(provenance.withUnsafeBytes { setxattr(file.path, "com.apple.provenance", $0.baseAddress, provenance.count, 0, 0) } == 0)
        // The OS can normalize this protected attribute as it is written.
        var storedProvenance = Data(count: provenance.count)
        #expect(storedProvenance.withUnsafeMutableBytes { getxattr(file.path, "com.apple.provenance", $0.baseAddress, provenance.count, 0, 0) } == provenance.count)
        let metadata = Data("preserved metadata".utf8)
        #expect(metadata.withUnsafeBytes { setxattr(file.path, "com.winway.fixture", $0.baseAddress, metadata.count, 0, 0) } == 0)

        for number in 2...3 {
            let report = await service.transfer(.init(sources: [file], destination: root, kind: .copy), resolveConflict: { _ in .keepBoth })
            #expect(report.succeeded == 1, "\(report.results)")
            let output = try #require(report.results.first?.destination)
            #expect(output.lastPathComponent == "memory-guide (\(number)).html")
            #expect(try Data(contentsOf: output) == Data(contentsOf: file))
            var copiedMetadata = Data(count: metadata.count)
            #expect(copiedMetadata.withUnsafeMutableBytes { getxattr(output.path, "com.winway.fixture", $0.baseAddress, metadata.count, 0, 0) } == metadata.count)
            #expect(copiedMetadata == metadata)
        }
        var originalProvenance = Data(count: provenance.count)
        #expect(originalProvenance.withUnsafeMutableBytes { getxattr(file.path, "com.apple.provenance", $0.baseAddress, provenance.count, 0, 0) } == provenance.count)
        #expect(originalProvenance == storedProvenance)
        #expect(try String(contentsOf: file, encoding: .utf8) == "<html>payload</html>")
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".winway-") }))
    }

    @Test func testConflictChoicesPartialFailureAndRepeatProtection() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let target = try await service.createDirectory(in: root, name: "target")
        let file = root.appendingPathComponent("a.txt")
        try write("source", file); try write("existing", target.appendingPathComponent("a.txt"))
        let request = FileTransferRequest(sources: [file, root.appendingPathComponent("missing")], destination: target, kind: .copy)
        let report = await service.transfer(request, resolveConflict: { _ in .keepBoth })
        #expect((report.state) == (.partial))
        #expect((report.succeeded) == (1)); #expect((report.failed) == (1))
        #expect((report.results.first?.destination?.lastPathComponent) == ("a (2).txt"))
        #expect((try String(contentsOf: target.appendingPathComponent("a.txt"), encoding: .utf8)) == ("existing"))
        let duplicate = await service.transfer(request)
        #expect((duplicate.results.first?.error?.code) == (.duplicateJob))
        let skipped = await service.transfer(.init(sources: [file], destination: target, kind: .copy))
        #expect((skipped.results.first?.outcome) == (.skipped))
        let cancelled = await service.transfer(.init(sources: [file, root.appendingPathComponent("missing")], destination: target, kind: .copy), resolveConflict: { _ in .cancel })
        #expect((cancelled.results.map(\.outcome)) == ([.cancelled, .cancelled]))
    }

    @Test func testDescendantAliasesAndMovingToSelfAreRejected() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let source = try await service.createDirectory(in: root, name: "source")
        let child = try await service.createDirectory(in: source, name: "child")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: child)
        for target in [source, child, alias] {
            let result = await service.transfer(.init(sources: [source], destination: target, kind: .copy))
            #expect((result.results.first?.error?.code) == (.invalidDestination))
        }
        let result = await service.transfer(.init(sources: [source], destination: root, kind: .move))
        #expect((result.results.first?.error?.code) == (.invalidDestination))
        let rootCopy = await service.transfer(.init(sources: [URL(fileURLWithPath: "/")], destination: root, kind: .copy))
        #expect((rootCopy.results.first?.error?.code) == (.invalidDestination))
    }

    @Test func testSameVolumeMoveAndBrokenSymlinkCopy() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let target = try await service.createDirectory(in: root, name: "target")
        let link = root.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")
        let copy = await service.transfer(.init(sources: [link], destination: target, kind: .copy))
        #expect((copy.succeeded) == (1) , "\(copy.results)")
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("broken").path)) == ("missing"))
        let file = root.appendingPathComponent("move.txt"); try write("move", file)
        let move = await service.transfer(.init(sources: [file], destination: target, kind: .move))
        #expect((move.succeeded) == (1))
        #expect(!(FileManager.default.fileExists(atPath: file.path)))
    }

    @Test func testCancellationFromProgressStopsRemainingItemsOffMainThread() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let target = try await service.createDirectory(in: root, name: "target")
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try write("a", a); try write("b", b)
        let cancel = FileOperationCancellation()
        let report = await service.transfer(.init(sources: [a, b], destination: target, kind: .copy), cancellation: cancel, onProgress: { progress in
            if progress.state == .running {
                #expect(!(Thread.isMainThread))
                if progress.processed == 1 { cancel.cancel() }
            }
        })
        #expect((report.results.map(\.outcome)) == ([.succeeded, .cancelled]))
    }

    @Test func testPermissionDeniedIsNotReportedAsEmpty() async throws {
        let root = try fixture(); defer { _ = chmod(root.path, 0o755); try? FileManager.default.removeItem(at: root) }
        #expect((chmod(root.path, 0)) == (0))
        do { _ = try await LocalFileService().listDirectory(root); Issue.record("must fail reading") }
        catch { #expect(((error as? FileServiceError)?.code) == (.permissionDenied)) }
    }

    @Test func testTargetCreatedDuringCopyIsNeverOverwritten() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let target = try await service.createDirectory(in: root, name: "target")
        let source = root.appendingPathComponent("race")
        try write("source", source)
        let targetFile = target.appendingPathComponent("race")
        let counter = ProgressCounter()
        let conflicts = ProgressCounter()
        let report = await service.transfer(.init(sources: [source], destination: target, kind: .copy), onProgress: { progress in
            if progress.state == .running && progress.currentSource != nil {
                switch counter.increment() {
                case 2: try! Data("competitor".utf8).write(to: targetFile)
                case 3: try! Data("another competitor".utf8).write(to: target.appendingPathComponent("race (2)"))
                default: break
                }
            }
        }, resolveConflict: { _ in
            _ = conflicts.increment()
            let staged = try! FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".winway-copy-") }
            #expect(staged.count == 1)
            if let copy = staged.first {
                #expect(try! String(contentsOf: copy, encoding: .utf8) == "source")
            }
            // A retry must commit the already prepared copy, not reread this changed source.
            try! Data("changed after copying".utf8).write(to: source)
            return .keepBoth
        })
        #expect((report.results.first?.outcome) == (.succeeded))
        #expect(conflicts.increment() == 3)
        #expect((report.results.first?.destination?.lastPathComponent) == ("race (3)"))
        #expect((try String(contentsOf: targetFile, encoding: .utf8)) == ("competitor"))
        #expect(try String(contentsOf: target.appendingPathComponent("race (2)"), encoding: .utf8) == "another competitor")
        #expect(try String(contentsOf: target.appendingPathComponent("race (3)"), encoding: .utf8) == "source")
        #expect(try String(contentsOf: source, encoding: .utf8) == "changed after copying")
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasPrefix(".winway-") }))
    }

    @Test func testLateConflictSkipAndCancelPreserveFilesAndCleanStaging() async throws {
        for kind in [FileTransferKind.copy, .move] {
            for choice in [FileConflictChoice.skip, .cancel, .keepBoth] {
                let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
                let service = LocalFileService()
                let target = try await service.createDirectory(in: root, name: "target")
                let source = root.appendingPathComponent("file.txt")
                let pending = root.appendingPathComponent("pending.txt")
                try write("source", source); try write("pending", pending)
                let counter = ProgressCounter()
                let cancellation = FileOperationCancellation()
                let report = await service.transfer(.init(sources: [source, pending], destination: target, kind: kind), cancellation: cancellation, onProgress: { progress in
                    if progress.state == .running && progress.currentSource == source && counter.increment() == 2 {
                        try! Data("competitor".utf8).write(to: target.appendingPathComponent("file.txt"))
                    }
                }, resolveConflict: { _ in
                    if choice == .keepBoth { cancellation.cancel() }
                    return choice
                })
                #expect(report.results.map(\.outcome) == (choice == .skip ? [.skipped, .succeeded] : [.cancelled, .cancelled]))
                #expect(report.results.allSatisfy { $0.residualURLs.isEmpty })
                #expect(try String(contentsOf: source, encoding: .utf8) == "source")
                #expect(try String(contentsOf: target.appendingPathComponent("file.txt"), encoding: .utf8) == "competitor")
                #expect(!(try FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasPrefix(".winway-") }))
            }
        }
    }

    @Test func testUnicodeAndCaseCollisionAreRejected() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        _ = try await service.createDirectory(in: root, name: "Café")
        do { _ = try await service.createDirectory(in: root, name: "Cafe\u{301}"); Issue.record("canonical equivalent collision") }
        catch { #expect(((error as? FileServiceError)?.code) == (.conflict)) }
        let sensitive = (try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])).volumeSupportsCaseSensitiveNames ?? false
        if !sensitive {
            do { _ = try await service.createDirectory(in: root, name: "CAFÉ"); Issue.record("case collision") }
            catch { #expect(((error as? FileServiceError)?.code) == (.conflict)) }
        }
    }

    /// Opt-in only: mount a dedicated disposable disk image and provide its directory.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WINWAY_TEST_VOLUME"] != nil)) func testRealCrossVolumeMoveIfFixtureMounted() async throws {
        guard let path = ProcessInfo.processInfo.environment["WINWAY_TEST_VOLUME"] else { return }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let volume = URL(fileURLWithPath: path)
        let target = volume.appendingPathComponent("winway-cross-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: target) }
        var sourceStat = stat(), targetStat = stat()
        #expect((lstat(root.path, &sourceStat)) == (0)); #expect((lstat(target.path, &targetStat)) == (0))
        #expect(sourceStat.st_dev != targetStat.st_dev , "fixture must really be another volume")
        let source = root.appendingPathComponent("Cross.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let file = source.appendingPathComponent("payload")
        try write("cross volume data", file)
        _ = chmod(file.path, 0o751)
        let metadata = Data("xattr across devices".utf8)
        #expect((metadata.withUnsafeBytes { setxattr(file.path, "com.winway.test", $0.baseAddress, metadata.count, 0, 0) }) == (0))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "payload")
        let result = await LocalFileService().transfer(.init(sources: [source], destination: target, kind: .move))
        #expect((result.succeeded) == (1) , "\(result.results)")
        #expect(!(FileManager.default.fileExists(atPath: source.path)))
        #expect((try String(contentsOf: target.appendingPathComponent("Cross.app/payload"), encoding: .utf8)) == ("cross volume data"))
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("Cross.app/link").path)) == ("payload"))
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".winway-") }))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WINWAY_TEST_VOLUME"] != nil)) func testSourceChangedDuringMoveConflictIsRestored() async throws {
        guard let path = ProcessInfo.processInfo.environment["WINWAY_TEST_VOLUME"] else { return }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let target = try await service.createDirectory(in: URL(fileURLWithPath: path), name: "conflict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: target) }
        let source = root.appendingPathComponent("file.txt")
        try write("original", source)
        let counter = ProgressCounter()
        let report = await service.transfer(.init(sources: [source], destination: target, kind: .move), onProgress: { progress in
            if progress.state == .running && progress.currentSource != nil && counter.increment() == 2 {
                try! Data("competitor".utf8).write(to: target.appendingPathComponent("file.txt"))
            }
        }, resolveConflict: { _ in
            try! Data("edited while deciding".utf8).write(to: source)
            return .keepBoth
        })
        let copy = target.appendingPathComponent("file (2).txt")
        #expect(report.results.first?.error?.code == .sourceChanged)
        #expect(report.results.first?.residualURLs == [copy])
        #expect(try String(contentsOf: source, encoding: .utf8) == "edited while deciding")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "original")
        #expect(try String(contentsOf: target.appendingPathComponent("file.txt"), encoding: .utf8) == "competitor")
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".winway-") }))
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasPrefix(".winway-") }))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WINWAY_TEST_VOLUME"] != nil)) func testMutationDuringCrossVolumeMovePreservesSource() async throws {
        guard let path = ProcessInfo.processInfo.environment["WINWAY_TEST_VOLUME"] else { return }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalFileService()
        let target = try await service.createDirectory(in: URL(fileURLWithPath: path), name: "mutation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: target) }
        let source = root.appendingPathComponent("changing")
        try Data(repeating: 65, count: 16 * 1_048_576).write(to: source)
        let count = ProgressCounter()
        let stop = FileOperationCancellation()
        let completed = DispatchSemaphore(value: 0)
        let report = await service.transfer(.init(sources: [source], destination: target, kind: .move), onProgress: { progress in
            if progress.state == .running && progress.currentSource != nil && count.increment() == 2 {
                DispatchQueue.global().async {
                    defer { completed.signal() }
                    let file = try! FileHandle(forWritingTo: source)
                    defer { try? file.close() }
                    var value: UInt8 = 0
                    while !stop.isCancelled {
                        try! file.seek(toOffset: 0)
                        try! file.write(contentsOf: Data([value]))
                        value &+= 1
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                }
            }
        })
        stop.cancel()
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { completed.wait(); continuation.resume() }
        }
        #expect((report.results.first?.error?.code) == (.sourceChanged) , "\(report.results)")
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!(FileManager.default.fileExists(atPath: target.appendingPathComponent("changing").path)))
        #expect((try FileManager.default.contentsOfDirectory(atPath: target.path)) == ([]))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WINWAY_TEST_READONLY_VOLUME"] != nil)) func testReadOnlyVolumeFailurePreservesSourceIfMounted() async throws {
        guard let path = ProcessInfo.processInfo.environment["WINWAY_TEST_READONLY_VOLUME"] else { return }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("readonly-failure-\(UUID().uuidString)")
        try write("must survive", source)
        let report = await LocalFileService().transfer(.init(sources: [source], destination: URL(fileURLWithPath: path), kind: .move))
        #expect((report.failed) == (1))
        #expect((report.results.first?.error?.code) == (.readOnly) , "\(report.results)")
        #expect((try String(contentsOf: source, encoding: .utf8)) == ("must survive"))
        #expect((report.results.first?.residualURLs) == ([]))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WINWAY_TEST_DISCONNECTED_PATH"] != nil)) func testDisconnectedVolumeIsNotEmptyIfFixtureProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["WINWAY_TEST_DISCONNECTED_PATH"] else { return }
        do { _ = try await LocalFileService().listDirectory(URL(fileURLWithPath: path)); Issue.record("unmounted path must fail") }
        catch { #expect(((error as? FileServiceError)?.code) == (.notFound)) }
    }
}

private final class ProgressCounter: @unchecked Sendable {
    let lock = NSLock()
    var count = 0
    func increment() -> Int { lock.withLock { count += 1; return count } }
}
