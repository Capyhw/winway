import Foundation
import Testing
@testable import WinwayCore

struct BrowserTabStateTests {
    @Test func fuzzyAndFilterMatchesAreNotFilteredAgainByLiteralName() {
        let root = URL(fileURLWithPath: "/fixture")
        let result = FileEntry(url: root.appendingPathComponent("main.swift"), name: "main.swift", isDirectory: false)
        var tab = BrowserTabState(directory: root)
        tab.filter = "mian ext:swift"
        tab.searchEntries = [result]
        tab.selection = [result.url]
        tab.reconcileSelection()
        #expect(tab.visibleEntries == [result])
        #expect(tab.selection == [result.url])
    }

    private let root = URL(fileURLWithPath: "/winway-test-browser")
    private func entries(_ count: Int) -> [FileEntry] {
        (1...count).reversed().map { index in
            let name = "Item \(index).txt"
            return FileEntry(url: root.appendingPathComponent(name), name: name,
                             isDirectory: index.isMultiple(of: 10), size: Int64(index),
                             modified: Date(timeIntervalSince1970: Double(index)),
                             kind: index.isMultiple(of: 10) ? "文件夹" : (index.isMultiple(of: 2) ? "图像" : "文本"))
        }
    }

    @Test func recursiveResultsRestoreDirectListingWhenSearchIsCleared() {
        var tab = BrowserTabState(directory: root)
        let direct = FileEntry(url: root.appendingPathComponent("direct.txt"), name: "direct.txt", isDirectory: false)
        let nested = FileEntry(url: root.appendingPathComponent("child/report.txt"), name: "report.txt", isDirectory: false)
        tab.entries = [direct]
        tab.filter = "report"
        tab.searchEntries = [nested]
        tab.selection = [nested.url]
        #expect(tab.visibleEntries == [nested])
        var other = tab
        other.searchEntries = []
        #expect(tab.visibleEntries == [nested])
        #expect(other.visibleEntries.isEmpty)
        tab.filter = ""
        tab.reconcileSelection()
        #expect(tab.visibleEntries == [direct])
        #expect(tab.selection.isEmpty)
        #expect(tab.entries == [direct])
    }

    @Test func derivedEntriesTrackMutationsWithoutSharingStateAcrossCopies() {
        var original = BrowserTabState(directory: root)
        original.entries = entries(3)
        let originalVisible = original.visibleEntries
        var copy = original
        copy.entries.append(FileEntry(url: root.appendingPathComponent("Item 4.txt"), name: "Item 4.txt", isDirectory: false))
        #expect(copy.visibleEntries.map(\.name) == ["Item 1.txt", "Item 2.txt", "Item 3.txt", "Item 4.txt"])
        copy.filter = "Item 2"
        #expect(copy.visibleEntries.map(\.name) == ["Item 2.txt"])
        copy.filter = ""
        copy.ascending = false
        #expect(copy.visibleEntries.map(\.name) == ["Item 4.txt", "Item 3.txt", "Item 2.txt", "Item 1.txt"])
        copy.entries.removeAll { $0.name == "Item 4.txt" }
        #expect(copy.visibleEntries.first?.name == "Item 3.txt")
        copy.selection = [copy.visibleEntries[0].url]
        copy.reconcileSelection()
        #expect(original.visibleEntries == originalVisible)
        #expect(original.selection.isEmpty)
        copy.entries = []
        #expect(copy.visibleEntries.isEmpty)
    }

    @Test func tenThousandEntriesSortNaturallyAndKeepFoldersFirst() {
        var tab = BrowserTabState(directory: root)
        tab.entries = entries(10_000)
        let original = tab.entries
        let ascending = tab.visibleEntries
        #expect(ascending.count == 10_000)
        #expect(Set(ascending.map(\.url)).count == 10_000)
        #expect(ascending.prefix(1_000).allSatisfy { $0.isDirectory })
        #expect(ascending.dropFirst(1_000).allSatisfy { !$0.isDirectory })
        #expect(ascending.first?.name == "Item 10.txt")
        #expect(ascending[999].name == "Item 10000.txt")
        #expect(ascending[1_000].name == "Item 1.txt")
        #expect(ascending[1_001].name == "Item 2.txt")
        #expect(ascending.last?.name == "Item 9999.txt")
        tab.ascending = false
        let descending = tab.visibleEntries
        #expect(descending.first?.name == "Item 10000.txt")
        #expect(descending[999].name == "Item 10.txt")
        #expect(descending[1_000].name == "Item 9999.txt")
        #expect(descending.last?.name == "Item 1.txt")
        #expect(tab.entries == original, "展示排序不得改变原始目录数据")
    }

    @Test func tenThousandEntriesSupportSizeDateAndKindSorts() {
        var tab = BrowserTabState(directory: root)
        tab.entries = entries(10_000)
        for sort in [FileSort.size, .modified, .kind] {
            tab.sort = sort
            for ascending in [true, false] {
                tab.ascending = ascending
                let visible = tab.visibleEntries
                #expect(visible.count == 10_000)
                #expect(visible.prefix(1_000).allSatisfy { $0.isDirectory })
                let files = Array(visible.dropFirst(1_000))
                let sorted = zip(files, files.dropFirst()).allSatisfy { first, second in
                    switch sort {
                    case .size: return ascending ? first.size <= second.size : first.size >= second.size
                    case .modified: return ascending ? first.modified <= second.modified : first.modified >= second.modified
                    case .kind:
                        let comparison = first.kind.localizedStandardCompare(second.kind)
                        return ascending ? comparison != .orderedDescending : comparison != .orderedAscending
                    case .name: return true
                    }
                }
                #expect(sorted, "\(sort.rawValue) 排序方向 \(ascending) 必须覆盖全部可见条目")
            }
        }
    }

    @Test func largeDirectoryFilteringIsCaseInsensitiveAndSelectionUsesVisibleIntersection() {
        var tab = BrowserTabState(directory: root)
        tab.entries = entries(10_000)
        let keep = root.appendingPathComponent("Item 100.txt")
        let filteredOut = root.appendingPathComponent("Item 99.txt")
        let removedFromDisk = root.appendingPathComponent("removed.txt")
        tab.selection = [keep, filteredOut, removedFromDisk]
        tab.filter = "iTeM 100"
        let filtered = tab.visibleEntries
        #expect(filtered.count == 12)
        #expect(Set(filtered.map(\.name)) == Set(([100] + Array(1000...1009) + [10000]).map { "Item \($0).txt" }))
        tab.reconcileSelection()
        #expect(tab.selection == [keep])
        tab.filter = ""
        tab.reconcileSelection()
        #expect(tab.selection == [keep], "取消过滤不会重新选中曾被过滤掉的项目")
        tab.entries.removeAll { $0.url == keep }
        tab.reconcileSelection()
        #expect(tab.selection.isEmpty, "刷新后外部删除的条目不得保留选择")
    }

    @Test func tabsRetainIndependentHistorySelectionSortFilterAndScroll() {
        var first = BrowserTabState(directory: root)
        var second = BrowserTabState(directory: root.appendingPathComponent("other"))
        first.entries = entries(20)
        second.entries = first.entries
        second.selection = [root.appendingPathComponent("Item 2.txt")]
        second.sort = .size
        second.ascending = false
        second.filter = "Item 2"
        second.scrollOffset = 420
        let originalHistory = second.navigation.history
        let originalVisible = second.visibleEntries
        let next = first.navigation.beginRequest()
        let accepted = first.navigation.commit(root.appendingPathComponent("child"), generation: next)
        #expect(accepted)
        first.filter = "nothing-matches"
        first.sort = .modified
        first.selection = [root.appendingPathComponent("Item 1.txt")]
        first.reconcileSelection()
        first.scrollOffset = 25
        first.entries.removeAll()
        #expect(first.id != second.id)
        #expect(second.navigation.history == originalHistory)
        #expect(second.visibleEntries == originalVisible)
        #expect(second.entries.count == 20)
        #expect(second.selection == [root.appendingPathComponent("Item 2.txt")])
        #expect(second.sort == .size)
        #expect(!second.ascending)
        #expect(second.filter == "Item 2")
        #expect(second.scrollOffset == 420)
    }
}
