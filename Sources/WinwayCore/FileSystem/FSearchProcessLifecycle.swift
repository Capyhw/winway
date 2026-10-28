import Foundation
import Darwin

/// Serializes client launch/cleanup with application shutdown. All mutable state
/// and Process access below are protected by `lock`.
final class FSearchProcessLifecycle: @unchecked Sendable {
    static let shared = FSearchProcessLifecycle(
        helperURL: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/fsearch"))

    private let lock = NSLock()
    private let helperPath: String
    private var stopping = false
    private var clients: [ObjectIdentifier: (Process, FileOperationCancellation)] = [:]

    init(helperURL: URL) {
        helperPath = helperURL.resolvingSymlinksInPath().path
    }

    func start(_ process: Process, cancellation: FileOperationCancellation) throws {
        try lock.withLock {
            guard !stopping, !cancellation.isCancelled else {
                throw FileServiceError(.cancelled, "搜索已取消")
            }
            try process.run()
            clients[ObjectIdentifier(process)] = (process, cancellation)
        }
    }

    func finish(_ process: Process) {
        lock.withLock {
            guard clients.removeValue(forKey: ObjectIdentifier(process)) != nil else { return }
            stopClients([process])
        }
    }

    func shutdown() {
        lock.withLock {
            guard !stopping else { return }
            stopping = true
            stopProcesses()
        }
    }

    /// Prevent launches while the service is stopped and its cache is maintained.
    func restart<T>(_ maintenance: () throws -> T) throws -> T {
        try lock.withLock {
            guard !stopping else { throw FileServiceError(.cancelled, "Winway 正在退出") }
            stopProcesses()
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while !helperProcesses().isEmpty, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
            guard helperProcesses().isEmpty else { throw FileServiceError(.io, "搜索服务未能退出，请重启 Winway 后再试。") }
            return try maintenance()
        }
    }

    private func stopProcesses() {
        for (_, cancellation) in clients.values { cancellation.cancel() }
        // Reap stdio clients first: none can spawn a new daemon after this.
        stopClients(clients.values.map { $0.0 })
        clients.removeAll()

        // FSearch detaches its daemon, so it is no longer our child. Match
        // only this app bundle's helper, including one left by an older run.
        // Never kill by name or trust the shared socket.lock's stale PID.
        let helpers = helperProcesses()
        for helper in helpers { helper.signal(SIGTERM, executablePath: helperPath) }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while helpers.contains(where: { $0.matches(executablePath: helperPath) }), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        for helper in helpers { helper.signal(SIGKILL, executablePath: helperPath) }
    }

    private func stopClients(_ processes: [Process]) {
        for process in processes where process.isRunning { process.terminate() }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while processes.contains(where: \.isRunning), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        for process in processes {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
    }

    private func helperProcesses() -> [HelperProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Leave room for processes launched between sizing and enumeration.
        var pids = [pid_t](repeating: 0, count: Int(count) + 128)
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, capacity) }
        guard found > 0 else { return [] }
        return pids.prefix(min(Int(found), pids.count)).compactMap { pid in
            guard pid > 1, pid != getpid(), let process = HelperProcess(pid: pid),
                  process.matches(executablePath: helperPath) else { return nil }
            return process
        }
    }

    private struct HelperProcess {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64

        init?(pid: pid_t) {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  info.pbi_uid == getuid() else { return nil }
            self.pid = pid
            startSeconds = info.pbi_start_tvsec
            startMicroseconds = info.pbi_start_tvusec
        }

        func matches(executablePath: String) -> Bool {
            guard let current = HelperProcess(pid: pid), current.startSeconds == startSeconds,
                  current.startMicroseconds == startMicroseconds else { return false }
            // PROC_PIDPATHINFO_MAXSIZE is a C expression macro unavailable to Swift.
            var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let size = UInt32(buffer.count)
            guard proc_pidpath(pid, &buffer, size) > 0 else { return false }
            let path = String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == executablePath
        }

        func signal(_ signal: Int32, executablePath: String) {
            // Recheck identity before each signal, including the kill fallback.
            if matches(executablePath: executablePath) { kill(pid, signal) }
        }
    }
}
