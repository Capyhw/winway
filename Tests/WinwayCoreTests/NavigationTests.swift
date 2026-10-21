import Testing
import Foundation
@testable import WinwayCore

struct NavigationTests {
    @Test func failedAndLateRequestsDoNotChangeHistory() {
        var state = NavigationState(directory: URL(fileURLWithPath: "/a"))
        let old = state.beginRequest()
        let current = state.beginRequest()
        let staleAccepted = state.commit(URL(fileURLWithPath: "/b"), generation: old)
        #expect(!staleAccepted)
        #expect(state.directory.path == "/a")
        let currentAccepted = state.commit(URL(fileURLWithPath: "/c"), generation: current)
        #expect(currentAccepted)
        #expect(state.history.map(\.path) == ["/a", "/c"])
    }
    @Test func branchClearsForwardHistory() {
        var state = NavigationState(directory: URL(fileURLWithPath: "/a"))
        for path in ["/b", "/c"] {
            let token = state.beginRequest()
            let accepted = state.commit(URL(fileURLWithPath: path), generation: token)
            #expect(accepted)
        }
        let back = state.beginRequest()
        let backAccepted = state.commit(URL(fileURLWithPath: "/b"), generation: back, historyIndex: 1)
        #expect(backAccepted)
        #expect(state.canGoForward)
        let branch = state.beginRequest()
        let branchAccepted = state.commit(URL(fileURLWithPath: "/d"), generation: branch)
        #expect(branchAccepted)
        #expect(state.history.map(\.path) == ["/a", "/b", "/d"])
        #expect(!state.canGoForward)
    }
}
