import Foundation

public struct BrowserTabState: Identifiable, Sendable {
    public let id: UUID
    public var navigation: NavigationState
    public var entries: [FileEntry] = [] { didSet { updateVisibleEntries() } }
    public var selection: Set<URL> = []
    public var filter = "" { didSet { if filter != oldValue { updateVisibleEntries() } } }
    public var searchEntries: [FileEntry]? { didSet { updateVisibleEntries() } }
    public var isSearching = false
    public var searchMessage: String?
    public var sort: FileSort = .name { didSet { if sort != oldValue { updateVisibleEntries() } } }
    public var ascending = true { didSet { if ascending != oldValue { updateVisibleEntries() } } }
    public var scrollOffset: Double = 0
    public var isLoading = false
    public var error: String?
    public init(id: UUID = UUID(), directory: URL) { self.id = id; self.navigation = NavigationState(directory: directory) }
    // Store derived values in the struct so copies remain independent and reads
    // during selection/preview updates never repeat the full directory sort.
    public private(set) var visibleEntries: [FileEntry] = []
    private mutating func updateVisibleEntries() {
        visibleEntries = (filter.isEmpty ? entries : searchEntries ?? entries).filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let order: ComparisonResult
            switch sort {
            case .name: order = a.name.localizedStandardCompare(b.name)
            case .kind: order = a.kind == b.kind ? a.name.localizedStandardCompare(b.name) : a.kind.localizedStandardCompare(b.kind)
            case .size: order = a.size == b.size ? a.name.localizedStandardCompare(b.name) : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .modified: order = a.modified == b.modified ? a.name.localizedStandardCompare(b.name) : (a.modified < b.modified ? .orderedAscending : .orderedDescending)
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
    public mutating func reconcileSelection() { selection.formIntersection(Set(visibleEntries.map(\.url))) }
}
