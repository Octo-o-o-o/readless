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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "Core",
            dependencies: [],
            path: "Sources/Core"
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

        // MARK: - UI
        .target(
            name: "UI",
            dependencies: ["Core"],
            path: "Sources/UI"
        ),

        // MARK: - App (executable)
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                "Networking",
                "Storage",
                "UI",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/App",
            exclude: ["Resources"],
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
        )
    ]
)
