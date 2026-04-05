// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLlama",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
    ],
    targets: [
        .target(name: "SwiftLlama",
                dependencies: [
                    "LlamaFramework"
                ]),
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b8661/llama-b8661-xcframework.zip",
            checksum: "aceb4340937d6a7e63853d3bde7c3888bcc991ad0e376b72a42d6aab08a9ca2d"
        )
    ]
)
