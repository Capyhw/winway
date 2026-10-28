import Foundation
import Darwin
import Testing
@testable import WinwayCore

struct FSearchProcessLifecycleTests {
    private func fixture() throws -> (URL, URL, FSearchProcessLifecycle) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-search-exit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helper = root.appendingPathComponent("fsearch")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: helper.path)
        // A copied Apple platform binary can be killed by macOS before it runs.
        // Give the fixture its own ad-hoc signature, like the bundled helper.
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", helper.path]
        signer.standardError = FileHandle.nullDevice
        try signer.run()
        signer.waitUntilExit()
        try #require(signer.terminationStatus == 0)
        return (root, helper, FSearchProcessLifecycle(helperURL: helper))
    }

    private func sleeper(_ executable: URL) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["30"]
        return process
    }

    private func cleanup(_ process: Process) {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    @Test func shutdownStopsBundledHelperButPreservesIndependentInstallation() throws {
        let (root, helper, lifecycle) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appendingPathComponent("independent/fsearch")
        try FileManager.default.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: helper, to: external)
        let bundledProcess = sleeper(helper), externalProcess = sleeper(external)
        try bundledProcess.run()
        defer { cleanup(bundledProcess) }
        try externalProcess.run()
        defer { cleanup(externalProcess) }
        try #require(bundledProcess.isRunning && externalProcess.isRunning)

        // Neither was registered as a stdio client: this also exercises cleanup
        // of a bundled daemon left running by an earlier version of Winway.
        lifecycle.shutdown()
        // Bound failed assertions too, especially for the stopped fixture below.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while bundledProcess.isRunning, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
        try #require(!bundledProcess.isRunning)
        bundledProcess.waitUntilExit()
        #expect(!bundledProcess.isRunning)
        #expect(bundledProcess.terminationStatus == SIGTERM)
        #expect(externalProcess.isRunning)
        lifecycle.shutdown()
        #expect(externalProcess.isRunning)
    }

    @Test func shutdownCancelsActiveClientsAndRejectsQueuedLaunches() throws {
        let (root, _, lifecycle) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let cancellation = FileOperationCancellation()
        let process = sleeper(URL(fileURLWithPath: "/bin/sleep"))
        try lifecycle.start(process, cancellation: cancellation)
        defer { cleanup(process) }
        lifecycle.shutdown()
        #expect(cancellation.isCancelled)
        #expect(!process.isRunning)
        lifecycle.finish(process)

        let queued = sleeper(URL(fileURLWithPath: "/bin/sleep"))
        #expect(throws: FileServiceError(.cancelled, "搜索已取消")) {
            try lifecycle.start(queued, cancellation: .init())
        }
        #expect(!queued.isRunning)
    }

    @Test func shutdownDoesNotHangOnUnresponsiveHelper() throws {
        let (root, helper, lifecycle) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let process = Process()
        // Ignored signals survive exec: exercise the exact helper executable,
        // while leaving this test runner's own signal dispositions unchanged.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; exec \"$1\" 30", "fsearch", helper.path]
        try process.run()
        defer { cleanup(process) }
        func helperHasStarted() -> Bool {
            var path = [UInt8](repeating: 0, count: 4096)
            guard proc_pidpath(process.processIdentifier, &path, 4096) > 0 else { return false }
            let url = URL(fileURLWithPath: String(decoding: path.prefix(while: { $0 != 0 }), as: UTF8.self))
            return url.resolvingSymlinksInPath() == helper.resolvingSymlinksInPath()
        }
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !helperHasStarted(), ContinuousClock.now < readyDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        try #require(helperHasStarted())
        let start = ContinuousClock.now
        lifecycle.shutdown()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while process.isRunning, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
        try #require(!process.isRunning)
        process.waitUntilExit()
        #expect(!process.isRunning)
        #expect(process.terminationStatus == SIGKILL)
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test func finishingAQueryKeepsTheDaemonAlive() throws {
        let (root, helper, lifecycle) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let daemon = sleeper(helper)
        try daemon.run()
        defer { cleanup(daemon) }
        let client = sleeper(URL(fileURLWithPath: "/bin/sleep"))
        try lifecycle.start(client, cancellation: .init())
        defer { cleanup(client) }
        lifecycle.finish(client)
        #expect(!client.isRunning)
        #expect(daemon.isRunning)
    }
}
