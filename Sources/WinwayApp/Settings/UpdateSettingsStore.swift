import AppKit
import Combine
import WinwayCore

@MainActor
final class UpdateSettingsStore: ObservableObject {
    enum State: Equatable {
        case idle, checking, current, available(String, URL), failed(String)
    }
    @Published private(set) var state: State = .idle
    let version: String
    let build: String
    private let fetch: @Sendable () async throws -> ReleaseUpdate
    private var task: Task<Void, Never>?

    init(version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "开发版",
         fetch: @escaping @Sendable () async throws -> ReleaseUpdate = { try await ReleaseUpdateClient().latest() }) {
        self.version = version; self.build = build; self.fetch = fetch
    }

    var message: String {
        switch state {
        case .idle: "从 GitHub 检查正式发布版本。"
        case .checking: "正在检查更新…"
        case .current: "当前已是最新版本。"
        case .available(let tag, _): "发现新版本 \(tag)"
        case .failed(let message): "检查失败：\(message)"
        }
    }
    func check() {
        guard state != .checking else { return }
        state = .checking
        task = Task { [weak self, fetch] in
            do {
                let release = try await fetch()
                guard let self, !Task.isCancelled else { return }
                state = try release.isNewer(than: version) ? .available(release.tag, release.url) : .current
            } catch {
                guard let self, !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }
}
