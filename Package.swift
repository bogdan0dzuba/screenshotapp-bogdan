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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .target(name: "ScreenshotCore"),
        .executableTarget(
            name: "ScreenshotApp",
            dependencies: [
                "ScreenshotCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]),
            ]
        ),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["ScreenshotCore"],
            path: "Tests/CoreChecks"
        ),
    ],
    swiftLanguageModes: [.v5]
)
