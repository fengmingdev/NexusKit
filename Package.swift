// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NexusKit",

    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],

    products: [
        // Core module (required for all other modules)
        .library(
            name: "NexusCore",
            targets: ["NexusCore"]
        ),

        // TCP module
        .library(
            name: "NexusTCP",
            targets: ["NexusCore", "NexusTCP"]
        ),

        // WebSocket module
        .library(
            name: "NexusWebSocket",
            targets: ["NexusCore", "NexusWebSocket"]
        ),

        // Socket.IO module
        .library(
            name: "NexusIO",
            targets: ["NexusCore", "NexusWebSocket", "NexusIO"]
        ),

        // Compatibility layer (NodeSocket adapter)
        .library(
            name: "NexusCompat",
            targets: ["NexusCore", "NexusTCP", "NexusCompat"]
        ),

        // Complete package (all modules)
        .library(
            name: "NexusKit",
            targets: [
                "NexusCore",
                "NexusTCP",
                "NexusWebSocket",
                "NexusIO",
                "NexusCompat"
            ]
        )

        // Middleware modules (暂未实现)
        // .library(
        //     name: "NexusMiddlewares",
        //     targets: [
        //         "NexusMiddlewareCompression",
        //         "NexusMiddlewareEncryption",
        //         "NexusMiddlewareLogging",
        //         "NexusMiddlewareMetrics"
        //     ]
        // )
    ],

    dependencies: [
        // Swift Protobuf for binary protocol support
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.20.0"
        ),

        // Swift Log for logging
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.5.0"
        ),

        // Optional: Swift NIO for high-performance networking (macOS/Linux)
        // Commented out for now to reduce dependencies
        // .package(
        //     url: "https://github.com/apple/swift-nio.git",
        //     from: "2.50.0"
        // ),

        // Swift DocC for documentation
        .package(
            url: "https://github.com/apple/swift-docc-plugin",
            from: "1.0.0"
        )
    ],

    targets: [
        // MARK: - Core Module

        .target(
            name: "NexusCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/NexusCore",
            swiftSettings: [
                .define("NEXUS_ENABLE_LOGGING", .when(configuration: .debug)),
                .define("NEXUS_PERFORMANCE_METRICS", .when(configuration: .debug))
            ]
        ),

        // MARK: - Protocol Modules

        .target(
            name: "NexusTCP",
            dependencies: [
                "NexusCore",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/NexusTCP"
        ),

        .target(
            name: "NexusWebSocket",
            dependencies: ["NexusCore"],
            path: "Sources/NexusWebSocket"
        ),

        .target(
            name: "NexusIO",
            dependencies: [
                "NexusCore",
                "NexusWebSocket"
            ],
            path: "Sources/NexusIO"
        ),

        // MARK: - Compatibility Layer

        .target(
            name: "NexusCompat",
            dependencies: [
                "NexusCore",
                "NexusTCP"
            ],
            path: "Sources/NexusCompat"
        ),

        // MARK: - Middleware Modules

        // .target(
        //     name: "NexusMiddlewareCompression",
        //     dependencies: ["NexusCore"],
        //     path: "Middlewares/NexusMiddlewareCompression"
        // ),

        // .target(
        //     name: "NexusMiddlewareEncryption",
        //     dependencies: ["NexusCore"],
        //     path: "Middlewares/NexusMiddlewareEncryption"
        // ),

        // .target(
        //     name: "NexusMiddlewareLogging",
        //     dependencies: [
        //         "NexusCore",
        //         .product(name: "Logging", package: "swift-log")
        //     ],
        //     path: "Middlewares/NexusMiddlewareLogging"
        // ),

        // .target(
        //     name: "NexusMiddlewareMetrics",
        //     dependencies: ["NexusCore"],
        //     path: "Middlewares/NexusMiddlewareMetrics"
        // ),

        // MARK: - Test Targets

        .testTarget(
            name: "NexusCoreTests",
            dependencies: ["NexusCore"],
            path: "Tests/NexusCoreTests"
        ),

        .testTarget(
            name: "NexusTCPTests",
            dependencies: ["NexusTCP"],
            path: "Tests/NexusTCPTests"
        ),

        // .testTarget(
        //     name: "NexusWebSocketTests",
        //     dependencies: ["NexusWebSocket"],
        //     path: "Tests/NexusWebSocketTests"
        // ),

        .testTarget(
            name: "NexusIOTests",
            dependencies: ["NexusIO"],
            path: "Tests/NexusIOTests"
        ),

        // .testTarget(
        //     name: "MiddlewareTests",
        //     dependencies: [
        //         "NexusMiddlewareCompression",
        //         "NexusMiddlewareEncryption",
        //         "NexusMiddlewareLogging",
        //         "NexusMiddlewareMetrics"
        //     ],
        //     path: "Tests/MiddlewareTests"
        // ),

        // .testTarget(
        //     name: "IntegrationTests",
        //     dependencies: [
        //         "NexusCore",
        //         "NexusTCP",
        //         "NexusWebSocket",
        //         "NexusIO",
        //         "NexusSecure"
        //     ],
        //     path: "Tests/IntegrationTests"
        // )
    ]
)
