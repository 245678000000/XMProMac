// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XMProMac",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "XMProCore",
            targets: ["XMProCore"]
        ),
        .executable(
            name: "XMProMac",
            targets: ["XMProMac"]
        ),
    ],
    targets: [
        .target(
            name: "XMProCore",
            dependencies: [],
            path: "Sources/XMProCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "XMProMac",
            dependencies: ["XMProCore"],
            path: "Sources/XMProMac",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "XMProCoreTests",
            dependencies: ["XMProCore"],
            path: "Tests/XMProCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
