import AppKit
import SwiftUI
import WinwayCore

actor SettingsFixture {
    var access = FullDiskAccess.denied
    var requests: [Bool] = []
    var stopped = 0
    var helperAccess = true
    var fail = false
    var remainingBuildResponses = 0
    func setAccess(_ value: FullDiskAccess) { access = value }
    func setHelperAccess(_ value: Bool) { helperAccess = value }
    func setFailure(_ value: Bool) { fail = value }
    func prepare(_ rebuild: Bool) throws {
        if fail { throw FileServiceError(.conflict, "索引被占用") }
        requests.append(rebuild)
        remainingBuildResponses = 1
    }
    func status() -> SearchIndexStatus {
        if remainingBuildResponses > 0 {
            remainingBuildResponses -= 1
            return SearchIndexStatus(isBuilding: true, fullDiskAccess: nil, entries: nil, pendingContent: nil)
        }
        return SearchIndexStatus(isBuilding: false, fullDiskAccess: helperAccess, entries: 12840, pendingContent: 0)
    }
    func stop() { stopped += 1 }
}

@main
struct SettingsRunner {
    @MainActor static func waitFor(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            precondition(ContinuousClock.now < deadline, message)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "winway-settings-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = SettingsFixture()
        let search = SearchSettingsStore(defaults: defaults, probe: { await fixture.access },
            prepare: { try await fixture.prepare($0) }, status: { _ in await fixture.status() },
            stopEngine: { await fixture.stop() })
        search.startMonitoring()
        defer { search.stop() }
        try await waitFor("First-run permission check") { search.access == .denied && !search.checkingAccess }
        precondition(search.showOnboarding && !search.canSearch)
        let beforeGrant = await fixture.requests
        precondition(beforeGrant.isEmpty, "Permission denial must never start indexing")
        search.rebuildIndex()
        let afterDeniedRebuild = await fixture.requests
        precondition(afterDeniedRebuild.isEmpty)
        search.dismissOnboarding()
        precondition(defaults.bool(forKey: "permissions.onboardingCompleted"))
        print("PASS: first-run guide, later choice persistence and no indexing before authorization")

        await fixture.setAccess(.granted)
        search.refreshAccess()
        try await waitFor("Index startup after permission grant") { search.canSearch }
        let initial = await fixture.requests
        precondition(initial == [false])
        search.refreshAccess()
        try await waitFor("Repeated permission check") { !search.checkingAccess }
        let afterFocus = await fixture.requests
        precondition(afterFocus == [false], "Already-ready index must not restart on focus")
        search.rebuildIndex()
        precondition(!search.canSearch)
        try await waitFor("Manual full reindex") { search.canSearch }
        let afterRebuild = await fixture.requests
        precondition(afterRebuild == [false, true])
        print("PASS: authorization automatically starts index, focus is idempotent, manual rebuild restarts search")

        await fixture.setAccess(.denied)
        search.refreshAccess()
        try await waitFor("Revocation stops searching") { search.access == .denied && !search.checkingAccess }
        precondition(!search.canSearch && search.indexState == .waiting)
        await fixture.setHelperAccess(false)
        await fixture.setAccess(.granted)
        search.refreshAccess()
        try await waitFor("Helper permission mismatch") { if case .failed = search.indexState { true } else { false } }
        precondition(!search.canSearch && search.engineAccess == false)
        await fixture.setHelperAccess(true)
        search.refreshAccess()
        try await waitFor("Return from system settings retries helper") { search.canSearch }
        await fixture.setFailure(true)
        search.rebuildIndex()
        try await waitFor("Reindex failure") { search.indexState == .failed("索引被占用") }
        precondition(!search.canSearch)
        await fixture.setFailure(false)
        search.rebuildIndex()
        try await waitFor("Reindex retry") { search.canSearch }
        print("PASS: revocation, helper mismatch, failed rebuild and retry")

        let releaseData = Data(#"{"tag_name":"v0.2.3","html_url":"https://github.com/Capyhw/winway/releases/tag/v0.2.3","draft":false,"prerelease":false}"#.utf8)
        let release = try JSONDecoder().decode(ReleaseUpdate.self, from: releaseData)
        let updates = UpdateSettingsStore(version: "0.1.0", build: "1", fetch: { release })
        updates.check()
        try await waitFor("Update available") { if case .available = updates.state { true } else { false } }
        let current = UpdateSettingsStore(version: "0.2.3", fetch: { release })
        current.check()
        try await waitFor("Already current") { current.state == .current }
        let failed = UpdateSettingsStore(fetch: { throw URLError(.notConnectedToInternet) })
        failed.check()
        try await waitFor("Network failure") { if case .failed = failed.state { true } else { false } }
        print("PASS: update available, no update and network failure states")

        if ProcessInfo.processInfo.environment["WINWAY_TEST_LIVE_UPDATES"] == "1" {
            let latest = try await ReleaseUpdateClient().latest()
            _ = try latest.isNewer(than: "0.1.0")
            print("PASS: live GitHub release check: \(latest.tag)")
        }

        if let path = ProcessInfo.processInfo.environment["WINWAY_SETTINGS_SCREENSHOTS"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let keyboard = KeyboardSettingsStore(configurationURL: directory.appendingPathComponent("keyboard.json"))
            let navigation = SettingsNavigation()
            for page in SettingsPage.allCases {
                navigation.selection = page
                try await capture(SettingsView(keyboard: keyboard, search: search, navigation: navigation),
                                  size: NSSize(width: 920, height: 650), at: directory.appendingPathComponent("\(page.id)-settings.png"))
            }
            navigation.selection = .permissions
            try await capture(SettingsView(keyboard: keyboard, search: search, navigation: navigation),
                              size: NSSize(width: 800, height: 520), at: directory.appendingPathComponent("permissions-compact.png"))
            await fixture.setAccess(.denied)
            search.refreshAccess()
            try await waitFor("Onboarding screenshot state") { search.access == .denied }
            try await capture(PermissionOnboardingView(store: search), size: NSSize(width: 570, height: 490),
                              at: directory.appendingPathComponent("onboarding.png"))
            print("PASS: rendered all settings sections and first-run guide")
        }
    }

    @MainActor static func capture<V: View>(_ view: V, size: NSSize, at url: URL) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size, "Hosting view escaped the requested window size")
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        window.orderOut(nil)
    }
}
