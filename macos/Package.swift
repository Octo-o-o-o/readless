// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Readless",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Library modules consumed by the Xcode app target
        .library(name: "Core", targets: ["Core"]),
        .library(name: "LiquidGlassKit", targets: ["LiquidGlassKit"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "AIServices", targets: ["AIServices"]),
        .library(name: "ReaderFeature", targets: ["ReaderFeature"]),
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
        .library(name: "Utils", targets: ["Utils"]),
        .library(name: "UI", targets: ["UI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts.git",
            from: "2.0.0"
        )
    ],
    targets: [
        // MARK: - Core (zero dependencies)
        .target(
            name: "Core",
            dependencies: [],
            path: "Sources/Core",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // MARK: - LiquidGlassKit (design system)
        .target(
            name: "LiquidGlassKit",
            dependencies: [],
            path: "Sources/LiquidGlassKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Networking
        .target(
            name: "Networking",
            dependencies: ["Core"],
            path: "Sources/Networking"
        ),

        // MARK: - Storage
        .target(
            name: "Storage",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/Storage"
        ),

        // MARK: - AI Services
        .target(
            name: "AIServices",
            dependencies: ["Core", "Networking"],
            path: "Sources/AIServices"
        ),

        // MARK: - Utils
        .target(
            name: "Utils",
            dependencies: [],
            path: "Sources/Utils"
        ),

        // MARK: - UI (legacy, will be deprecated)
        .target(
            name: "UI",
            dependencies: ["Core"],
            path: "Sources/UI"
        ),

        // MARK: - Features
        .target(
            name: "ReaderFeature",
            dependencies: ["Core", "LiquidGlassKit", "Networking", "AIServices"],
            path: "Sources/ReaderFeature"
        ),

        .target(
            name: "LibraryFeature",
            dependencies: ["Core", "LiquidGlassKit", "Networking"],
            path: "Sources/LibraryFeature"
        ),

        // MARK: - App sources are built by the Xcode project (Readless.xcodeproj)
        // The Xcode target references Sources/App/ directly and handles
        // signing, entitlements, and .app bundle creation automatically.

        // MARK: - Tests
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking"],
            path: "Tests/NetworkingTests"
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage"],
            path: "Tests/StorageTests"
        ),
        .testTarget(
            name: "LiquidGlassKitTests",
            dependencies: ["LiquidGlassKit"],
            path: "Tests/LiquidGlassKitTests"
        ),
        .testTarget(
            name: "AIServicesTests",
            dependencies: ["AIServices"],
            path: "Tests/AIServicesTests"
        )
    ]
)
