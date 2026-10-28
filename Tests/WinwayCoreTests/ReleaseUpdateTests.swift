import Foundation
import Testing
@testable import WinwayCore

struct ReleaseUpdateTests {
    @Test func comparesNumericVersionsInsteadOfStrings() throws {
        #expect(try #require(ReleaseVersion("v0.10.0")) > #require(ReleaseVersion("0.9.12")))
        #expect(ReleaseVersion("1.0.0") == ReleaseVersion("v1.0.0"))
        for value in ["", "1.2", "1.2.3-beta", "1.2.3.4", "v1.x.2", "1..2"] { #expect(ReleaseVersion(value) == nil) }
    }
    @Test func validatesReleaseBeforeOfferingDownload() throws {
        func release(tag: String = "v0.2.3", host: String = "github.com", prerelease: Bool = false) throws -> ReleaseUpdate {
            let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag,
                "html_url": "https://\(host)/Capyhw/winway/releases/tag/\(tag)", "draft": false, "prerelease": prerelease])
            return try JSONDecoder().decode(ReleaseUpdate.self, from: data)
        }
        #expect(try release().isNewer(than: "0.1.0"))
        #expect(try !release().isNewer(than: "0.2.3"))
        #expect(try !release().isNewer(than: "1.0.0"))
        #expect(throws: (any Error).self) { try release(host: "example.com").isNewer(than: "0.1.0") }
        #expect(throws: (any Error).self) { try release(prerelease: true).isNewer(than: "0.1.0") }
        #expect(throws: (any Error).self) { try release().isNewer(than: "dev") }
    }
}
