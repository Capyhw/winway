import AppKit

@main
struct SearchLifecycleRunner {
    @MainActor
    static func main() async throws {
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = appURL.deletingLastPathComponent()
        // The copied bundle contains a signed sleep executable at the helper's
        // path. Exercise real AppDelegate termination without changing the user's
        // shared FSearch index or stopping their installed application.
        let helper = Process()
        helper.executableURL = appURL.appendingPathComponent("Contents/Helpers/fsearch")
        helper.arguments = ["30"]
        let app = Process()
        app.executableURL = appURL.appendingPathComponent("Contents/MacOS/Winway")
        app.arguments = ["--directory", root.path, "--settings-path", root.appendingPathComponent("settings.json").path]
        app.standardOutput = FileHandle.nullDevice
        app.standardError = FileHandle.nullDevice
        try app.run()
        defer {
            if app.isRunning { kill(app.processIdentifier, SIGKILL) }
            app.waitUntilExit()
        }

        let launchDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while NSRunningApplication(processIdentifier: app.processIdentifier)?.isFinishedLaunching != true {
            precondition(app.isRunning && ContinuousClock.now < launchDeadline, "Copied Winway did not launch")
            try await Task.sleep(for: .milliseconds(20))
        }
        // Allow the first permission probe (bounded to 3 seconds) to settle;
        // startup is allowed to stop an old, unauthorized helper too.
        try await Task.sleep(for: .milliseconds(3500))
        try helper.run()
        defer {
            if helper.isRunning { kill(helper.processIdentifier, SIGKILL) }
            helper.waitUntilExit()
        }
        precondition(helper.isRunning, "Helper fixture exited before application termination")
        precondition(NSRunningApplication(processIdentifier: app.processIdentifier)?.terminate() == true,
                     "Could not request normal application termination")
        let exitDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while app.isRunning || helper.isRunning {
            precondition(ContinuousClock.now < exitDeadline, "Application exit left its FSearch helper running")
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(app.terminationStatus == 0, "Winway did not exit normally")
        precondition(helper.terminationStatus == SIGTERM, "Helper did not receive graceful termination")
        print("PASS: normal packaged Winway exit stops its bundled search helper")
    }
}
