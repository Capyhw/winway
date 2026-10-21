// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Winway",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Winway", targets: ["WinwayApp"]), .library(name: "WinwayCore", targets: ["WinwayCore"])],
    targets: [
        .target(name: "WinwayCore"),
        .executableTarget(name: "WinwayApp", dependencies: ["WinwayCore"], resources: [.copy("Resources")]),
        .testTarget(name: "WinwayCoreTests", dependencies: ["WinwayCore"])
    ],
    swiftLanguageModes: [.v6]
)
