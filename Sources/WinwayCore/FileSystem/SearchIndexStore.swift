import Foundation
import Darwin

public struct SearchIndexStatus: Sendable {
    public let isBuilding: Bool
    public let fullDiskAccess: Bool?
    public let entries: Int?
    public let pendingContent: Int?
    public init(isBuilding: Bool, fullDiskAccess: Bool?, entries: Int?, pendingContent: Int?) {
        self.isBuilding = isBuilding; self.fullDiskAccess = fullDiskAccess
        self.entries = entries; self.pendingContent = pendingContent
    }
}

struct SearchIndexStore: Sendable {
    var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FSearch")

    /// The upstream engine shares its store with other clients. Hold both locks
    /// before touching caches; never remove lock files or another service's data.
    func prepare(rebuild: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var descriptors: [Int32] = []
        defer { for descriptor in descriptors { flock(descriptor, LOCK_UN); close(descriptor) } }
        for name in ["socket.lock", "daemon.lock"] {
            let descriptor = open(directory.appendingPathComponent(name).path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw FileServiceError(.io, "无法访问搜索索引锁，请检查目录权限。") }
            descriptors.append(descriptor)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw FileServiceError(.conflict, "另一个 FSearch 正在使用索引。请先退出独立运行的 FSearch，再重试。")
            }
        }
        guard rebuild else { return }
        let backup = directory.appendingPathComponent(".winway-reindex-\(UUID())")
        try fm.createDirectory(at: backup, withIntermediateDirectories: false)
        var moved: [String] = []
        do {
            for name in ["index.bin", "skipped", "content"] where fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
                try fm.moveItem(at: directory.appendingPathComponent(name), to: backup.appendingPathComponent(name))
                moved.append(name)
            }
        } catch {
            for name in moved.reversed() {
                try? fm.moveItem(at: backup.appendingPathComponent(name), to: directory.appendingPathComponent(name))
            }
            throw error
        }
        // Only generated search caches are removed. Files being indexed and
        // frecency/user data are never touched.
        try? fm.removeItem(at: backup)
    }
}
