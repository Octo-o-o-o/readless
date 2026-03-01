// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Readless",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "App", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/clerk/clerk-ios.git", from: "1.0.0")
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

        // MARK: - App (executable)
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                "LiquidGlassKit",
                "Networking",
                "Storage",
                "AIServices",
                "ReaderFeature",
                "LibraryFeature",
                "Utils",
                "UI", // Keep UI for gradual migration
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "ClerkKit", package: "clerk-ios"),
                .product(name: "ClerkKitUI", package: "clerk-ios")
            ],
            path: "Sources/App",
            exclude: ["Resources", "Services/README_SuggestionEngine.md"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/App/Resources/Info.plist"
                ])
            ]
        ),

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
