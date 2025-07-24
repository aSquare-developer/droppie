import Vapor
import Fluent
import FluentPostgresDriver
import JWT
import Redis
import QueuesRedisDriver

// configures your application
public func configure(_ app: Application) async throws {
    
    // Settings for working in a local environment
//    app.http.server.configuration.hostname = "0.0.0.0"
//    
//    app.databases.use(
//        .postgres(
//            configuration: .init(
//                hostname: "localhost",
//                username: "droppie",
//                password: "test123",
//                database: "droppie",
//                tls: .disable
//            )
//        ),
//        as: .psql
//    )
//    
//    let redisConfig = try RedisConfiguration(
//        hostname: "localhost",
//        port: 6379,
//        pool: RedisConfiguration.PoolOptions(
//            maximumConnectionCount: RedisConnectionPoolSize.maximumActiveConnections(30),
//            minimumConnectionCount: 5
//        )
//    )
//    
//    app.redis.configuration = redisConfig
//    
//    app.queues.use(.redis(redisConfig))
//    
//    let routeJob = RouteDistanceJob()
//    app.queues.add(routeJob)
//    
//    try app.queues.startInProcessJobs(on: .default)
    
    var tls = TLSConfiguration.makeClientConfiguration()
    tls.certificateVerification = .none
    let nioSSLContext = try NIOSSLContext(configuration: tls)
    
    if let databaseURL = Environment.get("DATABASE_URL") {
        do {
            var postgresConfig = try SQLPostgresConfiguration(url: databaseURL)
            postgresConfig = SQLPostgresConfiguration(
                hostname: postgresConfig.coreConfiguration.host ?? "",
                port: postgresConfig.coreConfiguration.port ?? 5432,
                username: postgresConfig.coreConfiguration.username,
                password: postgresConfig.coreConfiguration.password,
                database: postgresConfig.coreConfiguration.database,
                tls: .require(nioSSLContext)
            )

            app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
        } catch {
            app.logger.report(error: error)
            fatalError("Invalid DATABASE_URL: \(error)")
        }
    } else {
        let config = SQLPostgresConfiguration(
            hostname: Environment.get("DB_HOST_NAME") ?? "",
            port: 5432,
            username: Environment.get("DB_USER_NAME") ?? "",
            password: Environment.get("DB_PASSWORD") ?? "",
            database: Environment.get("DB_NAME") ?? "",
            tls: .disable
        )

        app.databases.use(.postgres(configuration: config), as: .psql)
    }
    
    if let redisURL = Environment.get("REDIS_URL") {
        let redisConfig = try RedisConfiguration(
            url: redisURL,
            tlsConfiguration: tls)
        
        app.redis.configuration = redisConfig
        app.queues.use(.redis(redisConfig))
        
        let routeJob = RouteDistanceJob()
        app.queues.add(routeJob)
        
        try app.queues.startInProcessJobs(on: .default)
    }
    
    // Register migrations
    app.migrations.add(CreateUsersTableMigration())
    app.migrations.add(CreateRoutesTableMigration())
    app.migrations.add(AddDistanceToRoutes())
    
    // Register controllers
    try app.register(collection: UserController())
    try app.register(collection: RouteController())
    
    // JWT algorithms
    // Add HMAC with SHA-256 signer.
    
    guard let jwtSecret = Environment.get("JWT_SECRET"),
          let secretData = jwtSecret.data(using: .utf8) else {
        fatalError("JWT_SECRET is missing or invalid")
    }

    await app.jwt.keys.add(hmac: .init(from: secretData), digestAlgorithm: .sha256)

    // register routes
    try routes(app)
    
    try await app.autoMigrate()
}
