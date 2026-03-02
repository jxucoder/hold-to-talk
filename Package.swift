// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HoldToTalk",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "HoldToTalk",
            dependencies: ["WhisperKit"],
            path: "Sources/HoldToTalk",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
