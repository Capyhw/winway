import Foundation

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let size: Int64
    public let modified: Date
    public let kind: String
    public let isHidden: Bool

    public func location(relativeTo root: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if parent == rootPath { return "当前目录" }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        return parent.hasPrefix(prefix) ? String(parent.dropFirst(prefix.count)) : parent
    }

    public init(url: URL, name: String, isDirectory: Bool, isSymbolicLink: Bool = false,
                size: Int64 = 0, modified: Date = .distantPast, kind: String = "文件", isHidden: Bool = false) {
        self.url = url; self.name = name; self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink; self.size = size; self.modified = modified
        self.kind = kind; self.isHidden = isHidden
    }
}
