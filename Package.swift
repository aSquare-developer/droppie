// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "droppie",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        // 🐘 Fluent driver for Postgres.
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // JWT
        .package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),
        // Redis
        .package(url: "https://github.com/vapor/redis.git", from: "4.5.0"),
        // Queues Redis Driver
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.0.0")

    ],
    targets: [
        .executableTarget(
            name: "droppie",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "Redis", package: "redis"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver")
            ],
            swiftSettings: swiftSettings
        ),
//        .testTarget(
//            name: "droppieTests",
//            dependencies: [
//                .target(name: "droppie"),
//                .product(name: "VaporTesting", package: "vapor"),
//            ],
//            swiftSettings: swiftSettings
//        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
