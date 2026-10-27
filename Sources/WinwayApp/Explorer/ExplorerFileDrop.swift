import Foundation

enum ExplorerFileDrop {
    /// Resolve directory aliases before checking cycles. A selected symlink is
    /// moved as a link, so it must not absorb selections inside its target.
    static func movableSources(_ urls: [URL], to destination: URL) -> [URL]? {
        guard !urls.isEmpty, destination.isFileURL,
              (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              FileManager.default.isWritableFile(atPath: destination.path) else { return nil }
        let target = destination.resolvingSymlinksInPath().standardizedFileURL.path
        var seen = Set<String>()
        var sources: [(url: URL, path: String, directory: Bool)] = []
        for url in urls {
            guard url.isFileURL else { return nil }
            let url = url.standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return nil }
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            let path = URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent).path
            let directory = values.isDirectory == true && values.isSymbolicLink != true
            guard path != target, parent != target,
                  !directory || !isDescendant(target, of: path) else { return nil }
            sources.append((url, path, directory))
        }
        // Search results can contain both a folder and its children. Moving the
        // folder already moves those children; do not submit them a second time.
        return sources.filter { source in
            !sources.contains { $0.directory && isDescendant(source.path, of: $0.path) }
        }.map(\.url)
    }

    private static func isDescendant(_ path: String, of parent: String) -> Bool {
        path.hasPrefix(parent == "/" ? "/" : parent + "/") && path != parent
    }
}
