import AppKit
import WinwayCore

enum FullDiskAccess: String, Codable, Sendable {
    case granted, denied, unknown

    /// macOS has no public FDA status API. Probe access, without reading the
    /// database contents, using the same protected file as the pinned FSearch.
    static func current() -> Self {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if descriptor >= 0 { close(descriptor); return .granted }
        return errno == EPERM || errno == EACCES ? .denied : .unknown
    }

    /// A fresh subprocess avoids reusing a denial cached before System Settings
    /// changed the grant. It inherits responsibility from this running app.
    static func probe() async -> Self {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard Bundle.main.bundleIdentifier == "app.winway.desktop", let executable = Bundle.main.executableURL else {
                    continuation.resume(returning: current()); return
                }
                let process = Process(), pipe = Pipe()
                process.executableURL = executable
                process.arguments = ["--check-disk-access"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                    while process.isRunning, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let result = process.terminationStatus == 0 ? try? JSONDecoder().decode(Self.self, from: data) : nil
                    continuation.resume(returning: result ?? .unknown)
                } catch { continuation.resume(returning: .unknown) }
            }
        }
    }

    @MainActor static func openSettings() -> Bool {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
