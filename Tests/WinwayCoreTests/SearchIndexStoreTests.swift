import Foundation
import Darwin
import Testing
@testable import WinwayCore

struct SearchIndexStoreTests {
    @Test func rebuildRemovesOnlyGeneratedCaches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-index-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("content"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for name in ["index.bin", "skipped", "content/segment", "frecency", "daemon.log", "user-file.txt"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let store = SearchIndexStore(directory: root)
        try store.prepare(rebuild: false)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("index.bin").path))
        try store.prepare(rebuild: true)
        for name in ["index.bin", "skipped", "content"] { #expect(!fm.fileExists(atPath: root.appendingPathComponent(name).path)) }
        for name in ["frecency", "daemon.log", "user-file.txt", "socket.lock", "daemon.lock"] {
            #expect(fm.fileExists(atPath: root.appendingPathComponent(name).path))
        }
        try store.prepare(rebuild: true)
    }

    @Test(arguments: ["socket.lock", "daemon.lock"])
    func refusesToResetAnIndexUsedByAnotherEngine(_ name: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-index-lock-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let data = Data("saved-index".utf8)
        try data.write(to: root.appendingPathComponent("index.bin"))
        let descriptor = open(root.appendingPathComponent(name).path, O_RDWR | O_CREAT, 0o600)
        try #require(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        do { try SearchIndexStore(directory: root).prepare(rebuild: true); Issue.record("In-use cache was reset") }
        catch { #expect((error as? FileServiceError)?.code == .conflict) }
        #expect(try Data(contentsOf: root.appendingPathComponent("index.bin")) == data)
    }
}
