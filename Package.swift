// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HoldToTalk",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "HoldToTalk",
            dependencies: ["WhisperKit", "Sparkle"],
            path: "Sources/HoldToTalk",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
