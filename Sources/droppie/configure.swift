import Vapor
import Fluent
import FluentPostgresDriver
import JWT

// configures your application
public func configure(_ app: Application) async throws {
    
    app.http.server.configuration.hostname = "0.0.0.0"
    

    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Make connection to our database
    app.databases.use(
        .postgres(
            configuration: .init(
                hostname: "localhost",
                username: "droppie",
                password: "test123",
                database: "droppie",
                tls: .disable
            )
        ),
        as: .psql
    )
    
    // Register migrations
    app.migrations.add(CreateUsersTableMigration())
    app.migrations.add(CreateRoutesTableMigration())
    
    // Register controllers
    try app.register(collection: UserController())
    try app.register(collection: RouteController())
    
    // JWT algorithms
    // Add HMAC with SHA-256 signer.
    await app.jwt.keys.add(hmac: "secret", digestAlgorithm: .sha256)

    // register routes
    try routes(app)
}
