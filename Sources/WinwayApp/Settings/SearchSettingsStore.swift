import AppKit
import Combine
import WinwayCore

@MainActor
final class SearchSettingsStore: ObservableObject {
    enum IndexState: Equatable {
        case waiting, starting, building, ready, failed(String)
    }
    @Published private(set) var access: FullDiskAccess = .unknown
    @Published private(set) var checkingAccess = false
    @Published private(set) var indexState: IndexState = .waiting
    @Published private(set) var entryCount: Int?
    @Published private(set) var contentPending = 0
    @Published private(set) var engineAccess: Bool?
    @Published private(set) var showOnboarding = false
    private(set) var isMonitoring = false
    var willRestart: (() -> Void)?
    var didBecomeReady: (() -> Void)?

    private let defaults: UserDefaults
    private let probe: @Sendable () async -> FullDiskAccess
    private let prepare: @Sendable (Bool) async throws -> Void
    private let status: @Sendable (FileOperationCancellation) async throws -> SearchIndexStatus
    private let stopEngine: @Sendable () async throws -> Void
    private var observer: AnyCancellable?
    private var permissionTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var indexCancellation = FileOperationCancellation()
    private var generation = UUID()
    private var stopped = false

    init(service: LocalFileService, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        probe = { await FullDiskAccess.probe() }
        prepare = { try await service.prepareSearchIndex(rebuild: $0) }
        status = { try await service.searchIndexStatus(cancellation: $0) }
        stopEngine = { try await service.stopSearchIndex() }
    }

    // Dependency seam for permission transitions without altering system grants.
    init(defaults: UserDefaults, probe: @escaping @Sendable () async -> FullDiskAccess,
         prepare: @escaping @Sendable (Bool) async throws -> Void,
         status: @escaping @Sendable (FileOperationCancellation) async throws -> SearchIndexStatus,
         stopEngine: @escaping @Sendable () async throws -> Void = {}) {
        self.defaults = defaults; self.probe = probe; self.prepare = prepare
        self.status = status; self.stopEngine = stopEngine
    }

    var canSearch: Bool { access == .granted && engineAccess == true && indexState == .ready }
    var isBusy: Bool { indexState == .starting || indexState == .building }
    var indexMessage: String {
        switch indexState {
        case .waiting: return "开启完全磁盘访问权限后，自动建立搜索索引。"
        case .starting: return "正在启动搜索服务…"
        case .building: return "正在建立文件索引，完成后即可搜索。"
        case .ready:
            let count = entryCount.map { "已索引 \($0.formatted()) 个项目" } ?? "文件索引已就绪"
            return contentPending > 0 ? count + "，内容索引仍在更新。" : count
        case .failed(let message): return message
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        observer = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor in self?.refreshAccess() }
        }
        refreshAccess()
    }

    func refreshAccess() {
        guard !checkingAccess, !stopped else { return }
        checkingAccess = true
        permissionTask = Task { [weak self, probe] in
            let result = await probe()
            guard let self, !Task.isCancelled, !stopped else { return }
            let previous = access
            access = result; checkingAccess = false
            if result != .granted {
                if !defaults.bool(forKey: "permissions.onboardingCompleted") { showOnboarding = true }
                cancelIndex(); willRestart?(); engineAccess = nil; indexState = .waiting
                try? await stopEngine()
            } else if previous != .granted || indexState == .waiting {
                defaults.set(true, forKey: "permissions.onboardingCompleted")
                beginIndex(rebuild: false)
            } else if case .failed = indexState {
                // Returning from Settings also retries helper permission errors.
                beginIndex(rebuild: false)
            }
        }
    }

    func openSystemSettings() {
        if !FullDiskAccess.openSettings() { indexState = .failed("无法打开系统设置，请手动前往「隐私与安全性 → 完全磁盘访问权限」。") }
    }

    func dismissOnboarding() {
        defaults.set(true, forKey: "permissions.onboardingCompleted")
        showOnboarding = false
    }

    func rebuildIndex() {
        guard access == .granted, !isBusy, !stopped else { return }
        beginIndex(rebuild: true)
    }

    private func beginIndex(rebuild: Bool) {
        cancelIndex(); willRestart?()
        let token = UUID(); generation = token
        let cancellation = FileOperationCancellation(); indexCancellation = cancellation
        engineAccess = nil; entryCount = nil; contentPending = 0; indexState = .starting
        indexTask = Task { [weak self, prepare, status] in
            do {
                try await prepare(rebuild)
                while !Task.isCancelled && !cancellation.isCancelled {
                    let result = try await status(cancellation)
                    guard let self, generation == token, !stopped, !Task.isCancelled else { return }
                    engineAccess = result.fullDiskAccess
                    entryCount = result.entries; contentPending = result.pendingContent ?? 0
                    if result.isBuilding { indexState = .building }
                    else if result.fullDiskAccess == true {
                        let wasReady = indexState == .ready
                        indexState = .ready
                        if !wasReady { didBecomeReady?() }
                    } else {
                        indexState = .failed("搜索服务尚未获得完全磁盘访问权限。请重新授权 Winway 并重启；仍未生效时，可为内置 FSearch 单独授权。")
                        try? await stopEngine()
                        return
                    }
                    // Keep content-index status current, but don't keep polling
                    // an idle service once both indexes have settled.
                    if indexState == .ready && contentPending == 0 { return }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch {
                guard let self, generation == token, !stopped, !Task.isCancelled, !cancellation.isCancelled else { return }
                indexState = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelIndex() {
        generation = UUID(); indexCancellation.cancel(); indexTask?.cancel(); indexTask = nil
    }

    func stop() {
        stopped = true; observer = nil; permissionTask?.cancel(); cancelIndex()
    }
}
