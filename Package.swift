// swift-tools-version: 6.0
import Foundation
import PackageDescription

let isAppStoreBuild = ProcessInfo.processInfo.environment["APP_STORE"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
]

if !isAppStoreBuild {
    packageDependencies.append(
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0")
    )
}

var executableDependencies: [Target.Dependency] = ["WhisperKit"]

if !isAppStoreBuild {
    executableDependencies.append("Sparkle")
}

let package = Package(
    name: "HoldToTalk",
    platforms: [.macOS(.v15)],
    dependencies: packageDependencies,
    targets: [
        .executableTarget(
            name: "HoldToTalk",
            dependencies: executableDependencies,
            path: "Sources/HoldToTalk",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HoldToTalkTests",
            dependencies: ["HoldToTalk"],
            path: "Tests/HoldToTalkTests"
        ),
    ]
)
