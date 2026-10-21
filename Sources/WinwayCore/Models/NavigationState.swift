import Foundation

public struct NavigationState: Equatable, Sendable {
    public private(set) var history: [URL]
    public private(set) var index: Int
    public private(set) var generation: UInt64 = 0
    public var directory: URL { history[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < history.count }

    public init(directory: URL) { history = [directory.standardizedFileURL]; index = 0 }
    @discardableResult public mutating func beginRequest() -> UInt64 { generation &+= 1; return generation }
    public mutating func commit(_ url: URL, generation expected: UInt64, historyIndex: Int? = nil) -> Bool {
        guard expected == generation else { return false }
        if let target = historyIndex {
            guard history.indices.contains(target), history[target] == url.standardizedFileURL else { return false }
            index = target
        } else if directory != url.standardizedFileURL {
            history = Array(history.prefix(index + 1))
            history.append(url.standardizedFileURL)
            index = history.count - 1
        }
        return true
    }
}

public enum FileSort: String, CaseIterable, Sendable { case name, modified, kind, size }
