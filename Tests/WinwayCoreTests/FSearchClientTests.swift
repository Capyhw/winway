import Foundation
import Testing
@testable import WinwayCore

struct FSearchClientTests {
    private func fixture(_ body: String) throws -> (URL, FSearchClient) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-fsearch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fsearch")
        // Always consume stdin before returning, just as the real stdio client does.
        let script = "#!/bin/sh\nIFS= read -r request\nprintf '%s' \"$request\" > '\(root.path)/request.json'\n" + body
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, FSearchClient(executableURL: executable, timeout: 5))
    }

    @Test func scopeAndQueryAreSeparateJSONValues() throws {
        let (root, client) = try fixture("printf '%s\\n' '{\"ok\":true,\"hits\":[]}'\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("资料 \"引号\"\n空格")
        let query = "mian.swift in:/ ext:swift"
        _ = try client.search(directory: directory, query: query, cancellation: .init())
        let data = try Data(contentsOf: root.appendingPathComponent("request.json"))
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(request["in"] as? String == directory.path)
        #expect(request["q"] as? String == query)
        #expect(request["limit"] as? Int == 10_001)
    }

    @Test(arguments: [
        "printf '%s\\n' '{\"ok\":false,\"error\":\"bad query\"}'\n",
        "printf '%s\\n' '{\"ok\":true}'\n",
        "printf '%s\\n' 'not json'\n",
        "exit 1\n"
    ]) func failureIsNotAnEmptyResult(_ script: String) async throws {
        let (root, client) = try fixture(script)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await LocalFileService(searchClient: client).searchDirectory(root, query: "needle")
            Issue.record("Protocol/daemon errors must be surfaced")
        } catch { #expect((error as? FileServiceError)?.code == .io) }
    }

    @Test func timeoutDoesNotBlockTheSearchQueue() async throws {
        let (root, initial) = try fixture("exec /bin/sleep 30\n")
        var client = initial
        client.timeout = 0.3
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ContinuousClock.now
        do {
            _ = try await LocalFileService(searchClient: client).searchDirectory(root, query: "needle")
            Issue.record("Unresponsive client must time out")
        } catch { #expect((error as? FileServiceError)?.message.contains("超时") == true) }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test func cancellationInterruptsAClientWaitingForOutput() async throws {
        let (root, initial) = try fixture("exec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: root) }
        var client = initial
        client.timeout = 30
        let service = LocalFileService(searchClient: client)
        let cancellation = FileOperationCancellation()
        let task = Task { try await service.searchDirectory(root, query: "needle", cancellation: cancellation) }
        try await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        cancellation.cancel()
        do { _ = try await task.value; Issue.record("Cancelled query returned a result") }
        catch { #expect((error as? FileServiceError)?.code == .cancelled) }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test func applicationShutdownInterruptsAnInFlightSearch() async throws {
        let (root, initial) = try fixture("exec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let lifecycle = FSearchProcessLifecycle(helperURL: root.appendingPathComponent("fsearch"))
        var client = initial
        client.lifecycle = lifecycle
        let service = LocalFileService(searchClient: client)
        let task = Task { try await service.searchDirectory(root, query: "needle") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("request.json").path),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        lifecycle.shutdown()
        do { _ = try await task.value; Issue.record("Shutdown search returned a result") }
        catch { #expect((error as? FileServiceError)?.code == .cancelled) }
        do { _ = try await service.searchDirectory(root, query: "another"); Issue.record("Search restarted after shutdown") }
        catch { #expect((error as? FileServiceError)?.code == .cancelled) }
    }

    @Test func contentResultsAndTruncationAreReported() async throws {
        let (root, client) = try fixture("/bin/cat \"$(dirname \"$0\")/response.json\"\nprintf '\\n'\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("report.txt")
        try Data("searchable content".utf8).write(to: file)
        let hits = Array(repeating: ["path": file.path], count: 10_001)
        try JSONSerialization.data(withJSONObject: ["ok": true, "files": hits, "complete": false, "indexing": 2])
            .write(to: root.appendingPathComponent("response.json"))
        let result = try await LocalFileService(searchClient: client).searchDirectory(root, query: "grep:searchable")
        #expect(result.entries.map(\.name) == ["report.txt"])
        #expect(result.isTruncated)
        #expect(result.isIndexing)
    }

    @Test func protectedDirectoriesDoNotLookLikeEmptyResults() throws {
        let (root, client) = try fixture("""
        case "$request" in
          *'"op":"status"'*) printf '%s\\n' '{"ok":true,"full_disk_access":false}' ;;
          *) printf '%s\\n' '{"ok":true,"hits":[]}' ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        do {
            _ = try client.search(directory: home.appendingPathComponent("Desktop"), query: "needle", cancellation: .init())
            Issue.record("Skipped protected directory must be explicit")
        } catch { #expect((error as? FileServiceError)?.code == .permissionDenied) }
        let result = try client.search(directory: home, query: "needle", cancellation: .init())
        #expect(result.limitedAccess)
    }
}
