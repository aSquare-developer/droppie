import Vapor
import Fluent
import FluentPostgresDriver
import JWT
import Redis
import QueuesRedisDriver
import Leaf
import NIOSSL

public func configure(_ app: Application) async throws {

    app.views.use(.leaf)

    // MARK: - Database (Postgres)
    if let databaseURL = Environment.get("DATABASE_URL") {
        // Production (Heroku, Render, Fly.io)
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .none

        let nioSSLContext = try NIOSSLContext(configuration: tls)
        var config = try SQLPostgresConfiguration(url: databaseURL)
        config.coreConfiguration.tls = .require(nioSSLContext)

        app.databases.use(.postgres(configuration: config), as: .psql)

    } else {
        // Local development
        app.databases.use(
            .postgres(
                configuration: .init(
                    hostname: Environment.get("DB_HOST") ?? "127.0.0.1",
                    port: 5432,
                    username: Environment.get("DB_USER") ?? "droppie",
                    password: Environment.get("DB_PASS") ?? "test123",
                    database: Environment.get("DB_NAME") ?? "droppie",
                    tls: .disable
                )
            ),
            as: .psql
        )
    }

    // MARK: - Redis (Cache + Queues)
    if let redisURL = Environment.get("REDIS_URL") {
        // Production Redis
        let redisConfig = try RedisConfiguration(url: redisURL)
        app.redis.configuration = redisConfig
        app.queues.use(.redis(redisConfig))

    } else {
        // Local Redis
        let redisConfig = try RedisConfiguration(
            hostname: "127.0.0.1",
            port: 6379,
            pool: .init(
                maximumConnectionCount: .maximumActiveConnections(30),
                minimumConnectionCount: 5
            )
        )
        app.redis.configuration = redisConfig
        app.queues.use(.redis(redisConfig))
    }

    // MARK: - Queues setup
    app.queues.add(RouteDistanceJob())
    // Only in production!
    if app.environment == .production {
        try app.queues.startInProcessJobs(on: .default)
    }

    // MARK: - JWT
    guard let jwtSecret = Environment.get("JWT_SECRET"),
          let secretData = jwtSecret.data(using: .utf8)
    else { fatalError("JWT_SECRET is missing in production!") }

    await app.jwt.keys.add(hmac: .init(from: secretData), digestAlgorithm: .sha256)

    // MARK: - Migrations
    app.migrations.add(CreateUsersTableMigration())
    app.migrations.add(CreateRoutesTableMigration())
    app.migrations.add(AddDistanceToRoutes())

    // MARK: - Controllers
    try app.register(collection: UserController())
    try app.register(collection: RouteController())

    // MARK: - Automigrate only locally
    if app.environment != .production {
        try await app.autoMigrate()
    }
}
