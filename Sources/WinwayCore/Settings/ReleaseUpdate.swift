import Foundation

public struct ReleaseVersion: Comparable, Sendable {
    public let components: [UInt]
    public init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { UInt($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct ReleaseUpdate: Decodable, Sendable {
    public let tag: String
    public let url: URL
    public let draft: Bool
    public let prerelease: Bool
    enum CodingKeys: String, CodingKey {
        case tag = "tag_name", url = "html_url", draft, prerelease
    }
    public func isNewer(than current: String) throws -> Bool {
        guard !draft, !prerelease, let latest = ReleaseVersion(tag), let installed = ReleaseVersion(current),
              url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Capyhw/winway/releases/tag/") else {
            throw FileServiceError(.io, "更新信息格式不受支持，请到项目发布页查看。")
        }
        return latest > installed
    }
}

public struct ReleaseUpdateClient: Sendable {
    public init() {}
    public func latest() async throws -> ReleaseUpdate {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Capyhw/winway/releases/latest")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Winway", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FileServiceError(.io, "无法读取更新服务器响应。") }
        switch response.statusCode {
        case 200: return try JSONDecoder().decode(ReleaseUpdate.self, from: data)
        case 404: throw FileServiceError(.notFound, "暂时没有可用的正式发布版本。")
        case 403, 429: throw FileServiceError(.io, "更新检查过于频繁，请稍后重试。")
        default: throw FileServiceError(.io, "更新服务器暂时不可用（\(response.statusCode)）。")
        }
    }
}
