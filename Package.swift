// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslateShortcut",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TranslateShortcut", targets: ["TranslateShortcut"])],
    targets: [
        .target(name: "TranslationCore"),
        .executableTarget(name: "TranslateShortcut", dependencies: ["TranslationCore"]),
        .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore"])
    ]
)
