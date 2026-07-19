// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenshotApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenshotCore", targets: ["ScreenshotCore"]),
        .executable(name: "ScreenshotApp", targets: ["ScreenshotApp"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
    ],
    targets: [
        .target(name: "ScreenshotCore"),
        .executableTarget(name: "ScreenshotApp", dependencies: ["ScreenshotCore"]),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["ScreenshotCore"],
            path: "Tests/CoreChecks"
        ),
    ],
    swiftLanguageModes: [.v5]
)
