import AppKit
import Foundation

struct BundleCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw BundleCheckFailure(message) }
}

func requireContained(_ resource: URL, within appURL: URL) throws {
    let resolved = resource.resolvingSymlinksInPath().standardizedFileURL.path
    let root = appURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    try require(resolved.hasPrefix(root), "Resource escapes copied application: \(resource.path)")
}

@MainActor
func checkBundle(at applicationURL: URL) throws -> [String: Any] {
    guard let application = Bundle(url: applicationURL), let resourceRoot = application.resourceURL else {
        throw BundleCheckFailure("Foundation could not resolve the copied application Bundle")
    }
    try require(application.bundleIdentifier == "app.winway.desktop", "Unexpected application bundle identifier")
    try require(application.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL", "Bundle package type is not APPL")
    guard let executable = application.executableURL else { throw BundleCheckFailure("Application executable is missing") }
    try requireContained(executable, within: applicationURL)
    try require(FileManager.default.isExecutableFile(atPath: executable.path), "Application binary is not executable")
    let searchHelper = applicationURL.appendingPathComponent("Contents/Helpers/fsearch")
    try requireContained(searchHelper, within: applicationURL)
    try require(FileManager.default.isExecutableFile(atPath: searchHelper.path), "Bundled FSearch helper is missing")
    try require(FileManager.default.fileExists(atPath: resourceRoot.appendingPathComponent("FSearch-LICENSE.txt").path), "FSearch license is missing")

    // This is the first candidate used by SwiftPM's generated Bundle.module
    // accessor in the packaged application. No build-directory fallback is used.
    let moduleURL = resourceRoot.appendingPathComponent("Winway_WinwayApp.bundle")
    try requireContained(moduleURL, within: applicationURL)
    guard let module = Bundle(url: moduleURL) else {
        throw BundleCheckFailure("SwiftPM resource bundle is missing from Contents/Resources")
    }
    guard let manifestURL = module.url(forResource: "manifest", withExtension: "json", subdirectory: "Resources/Figma") else {
        throw BundleCheckFailure("Figma resource manifest cannot be located through Bundle lookup")
    }
    try requireContained(manifestURL, within: applicationURL)
    let assetDirectory = manifestURL.deletingLastPathComponent()
    let names = ["pc", "view", "document", "excel", "word", "folder", "network", "drive",
                 "video", "music", "gallery", "download", "cloud", "home", "more", "down",
                 "sort", "delete", "rename", "paste", "copy", "cut", "plus", "search", "right",
                 "up", "forward", "back", "close", "macOsWindowControls", "pinnedShortcut",
                 "misc", "pdf", "word1"]
    let pngs = try FileManager.default.contentsOfDirectory(at: assetDirectory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasSuffix("@2x.png") }
    try require(pngs.count == names.count, "Expected exactly 34 runtime @2x PNG assets; found \(pngs.count)")
    var decoded: [[String: Any]] = []
    for name in names {
        // Match the production ExplorerStyle.image resource lookup exactly.
        guard let url = module.url(forResource: name + "@2x", withExtension: "png", subdirectory: "Resources/Figma") else {
            throw BundleCheckFailure("Missing runtime icon: \(name)")
        }
        try requireContained(url, within: applicationURL)
        let data = try Data(contentsOf: url)
        try require(!data.isEmpty, "Empty PNG: \(name)")
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.cgImage != nil,
              let image = NSImage(contentsOf: url), !image.representations.isEmpty else {
            throw BundleCheckFailure("AppKit could not decode PNG: \(name)")
        }
        try require(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "Invalid PNG geometry: \(name)")
        try require(bitmap.hasAlpha, "PNG lost transparency: \(name)")
        let expectedSize: (Int, Int)
        switch name {
        case "macOsWindowControls": expectedSize = (192, 88)
        case "word1": expectedSize = (80, 80)
        case "pinnedShortcut": expectedSize = (32, 32)
        case "misc": expectedSize = (28, 28)
        case "pdf": expectedSize = (40, 40)
        default: expectedSize = (48, 48)
        }
        try require(bitmap.pixelsWide == expectedSize.0 && bitmap.pixelsHigh == expectedSize.1,
                    "Unexpected @2x geometry for \(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        decoded.append(["name": name, "pixelsWide": bitmap.pixelsWide, "pixelsHigh": bitmap.pixelsHigh])
    }

    guard let iconName = application.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, !iconName.isEmpty else {
        throw BundleCheckFailure("CFBundleIconFile is absent")
    }
    let iconBase = (iconName as NSString).deletingPathExtension
    guard let iconURL = application.url(forResource: iconBase, withExtension: "icns") else {
        throw BundleCheckFailure("Application ICNS icon is absent from Contents/Resources")
    }
    try requireContained(iconURL, within: applicationURL)
    let iconData = try Data(contentsOf: iconURL)
    guard !iconData.isEmpty, let icon = NSImage(data: iconData), !icon.representations.isEmpty else {
        throw BundleCheckFailure("AppKit could not decode the application icon")
    }
    return ["result": "passed", "bundleIdentifier": application.bundleIdentifier ?? "",
            "resourceBundle": "Contents/Resources/Winway_WinwayApp.bundle",
            "runtimePNGCount": decoded.count, "pngs": decoded,
            "appIcon": iconURL.lastPathComponent,
            "scope": "Copied-bundle resource validation only; no application launch, window, screen capture, or UI acceptance."]
}

@MainActor
func run() -> Int32 {
    do {
        guard CommandLine.arguments.count == 2 else { throw BundleCheckFailure("Usage: bundle-runner /path/to/Winway.app") }
        let report = try checkBundle(at: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
        return 0
    } catch {
        FileHandle.standardError.write(Data("Bundle validation failed: \(error)\n".utf8))
        return 1
    }
}

exit(run())
