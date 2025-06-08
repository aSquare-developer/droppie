import Vapor
import Fluent
import FluentPostgresDriver
import JWT

// configures your application
public func configure(_ app: Application) async throws {
    
//    app.http.server.configuration.hostname = "0.0.0.0"
    
    if let databaseURL = Environment.get("DATABASE_URL"), var postgresConfig = PostgresConfiguration(url: databaseURL) {
        postgresConfig.tlsConfiguration = .makeClientConfiguration()
        postgresConfig.tlsConfiguration?.certificateVerification = .none
        app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
    } else {
        app.databases.use(
            .postgres(
                configuration: .init(
                    hostname: Environment.get("DB_HOST_NAME") ?? "",
                    username: Environment.get("DB_USER_NAME") ?? "",
                    password: Environment.get("DB_PASSWORD") ?? "",
                    database: Environment.get("DB_NAME") ?? "",
                    tls: .disable
                )
            ),
            as: .psql
        )
    }
    
    // Register migrations
    app.migrations.add(CreateUsersTableMigration())
//    app.migrations.add(CreateProfilesTableMigration())
    app.migrations.add(CreateRoutesTableMigration())
//    app.migrations.add(CreateRoutesListTableMigration())
    
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
}
