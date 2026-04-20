import Vapor
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import JWT
import Redis
import QueuesRedisDriver
import Leaf
import FluentSQL

struct AppConfigurationError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

// configures your application
public func configure(_ app: Application) async throws {
    app.views.use(.leaf)

    let jwtSecret = try requireEnvironment("JWT_SECRET", allowTestingDefault: app.environment == .testing)
    let jwtSecretData = try data(for: jwtSecret, variableName: "JWT_SECRET")
    let googleRoutesAPIKey = Environment.get("GOOGLE_ROUTES_API_KEY")
    let jwtLifetime = max(doubleEnvironment("JWT_ACCESS_TOKEN_LIFETIME_SECONDS") ?? 86_400, 300)
    let jwtRefreshLifetime = max(doubleEnvironment("JWT_REFRESH_TOKEN_LIFETIME_SECONDS") ?? 2_592_000, jwtLifetime)
    let autoMigrateOnStartup = boolEnvironment("AUTO_MIGRATE") ?? false
    let authRateLimitMaxAttempts = max(intEnvironment("AUTH_RATE_LIMIT_MAX_ATTEMPTS") ?? 10, 1)
    let authRateLimitWindow = max(doubleEnvironment("AUTH_RATE_LIMIT_WINDOW_SECONDS") ?? 60, 1)
    let authRateLimitBlockDuration = max(doubleEnvironment("AUTH_RATE_LIMIT_BLOCK_DURATION_SECONDS") ?? 900, 1)
    let corsAllowedOrigins = csvEnvironment("CORS_ALLOWED_ORIGINS")
    let enableHSTS = boolEnvironment("ENABLE_HSTS") ?? (app.environment == .production)
    let emailProvider = emailProviderEnvironment("EMAIL_PROVIDER") ?? .logger
    let emailAPIBaseURL = Environment.get("EMAIL_API_BASE_URL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "https://api.resend.com"
    let emailAPIKey = Environment.get("EMAIL_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let emailFromAddress = Environment.get("EMAIL_FROM_ADDRESS")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let emailFromName = Environment.get("EMAIL_FROM_NAME")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let emailReplyToAddress = Environment.get("EMAIL_REPLY_TO_ADDRESS")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let appBaseURL = Environment.get("APP_BASE_URL")?.trimmingCharacters(in: .whitespacesAndNewlines)

    try validateEmailConfiguration(
        provider: emailProvider,
        apiKey: emailAPIKey,
        fromAddress: emailFromAddress
    )

    app.appConfiguration = .init(
        googleRoutesAPIKey: googleRoutesAPIKey,
        queueProcessingEnabled: false,
        autoMigrateOnStartup: autoMigrateOnStartup,
        jwtAccessTokenLifetime: jwtLifetime,
        jwtRefreshTokenLifetime: jwtRefreshLifetime,
        authRateLimitMaxAttempts: authRateLimitMaxAttempts,
        authRateLimitWindow: authRateLimitWindow,
        authRateLimitBlockDuration: authRateLimitBlockDuration,
        corsAllowedOrigins: corsAllowedOrigins,
        enableHSTS: enableHSTS
    )
    app.emailConfiguration = .init(
        provider: emailProvider,
        fromEmail: emailFromAddress,
        fromName: emailFromName,
        replyToEmail: emailReplyToAddress,
        apiBaseURL: emailAPIBaseURL,
        apiKey: emailAPIKey,
        appBaseURL: appBaseURL
    )

    try configureMiddleware(app)

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.databases.default(to: .sqlite)
    } else if let databaseURL = Environment.get("DATABASE_URL") {
        do {
            let postgresConfig = try SQLPostgresConfiguration(url: databaseURL)
            app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
        } catch {
            app.logger.report(error: error)
            throw AppConfigurationError(message: "Invalid DATABASE_URL: \(error.localizedDescription)")
        }
    } else {
        let shouldUseDatabaseTLS = boolEnvironment("DB_TLS") ?? false
        let config = SQLPostgresConfiguration(
            hostname: try requireEnvironment("DB_HOST_NAME"),
            port: 5432,
            username: try requireEnvironment("DB_USER_NAME"),
            password: try requireEnvironment("DB_PASSWORD"),
            database: try requireEnvironment("DB_NAME"),
            tls: shouldUseDatabaseTLS ? .prefer(try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())) : .disable
        )

        app.databases.use(.postgres(configuration: config), as: .psql)
    }

    if let redisURL = Environment.get("REDIS_URL") {
        do {
            let redisConfig = try redisConfiguration(from: redisURL)
            app.redis.configuration = redisConfig
            app.queues.use(.redis(redisConfig))

            let routeJob = RouteDistanceJob()
            app.queues.add(routeJob)
            try app.queues.startInProcessJobs(on: .default)

            app.appConfiguration = .init(
                googleRoutesAPIKey: googleRoutesAPIKey,
                queueProcessingEnabled: googleRoutesAPIKey != nil,
                autoMigrateOnStartup: autoMigrateOnStartup,
                jwtAccessTokenLifetime: jwtLifetime,
                jwtRefreshTokenLifetime: jwtRefreshLifetime,
                authRateLimitMaxAttempts: authRateLimitMaxAttempts,
                authRateLimitWindow: authRateLimitWindow,
                authRateLimitBlockDuration: authRateLimitBlockDuration,
                corsAllowedOrigins: corsAllowedOrigins,
                enableHSTS: enableHSTS
            )

            if googleRoutesAPIKey == nil {
                app.logger.warning("REDIS_URL is configured, but GOOGLE_ROUTES_API_KEY is missing. Route distance jobs will be skipped.")
            }
        } catch {
            app.logger.error("Failed to configure Redis/queues: \(error.localizedDescription)")
        }
    } else {
        app.logger.warning("REDIS_URL is not configured. Route distance jobs are disabled.")
    }

    // Register migrations
    app.migrations.add(CreateUsersTableMigration())
    app.migrations.add(AddEmailAuthFieldsToUsers())
    app.migrations.add(CreateRoutesTableMigration())
    app.migrations.add(CreateProfilesTableMigration())
    app.migrations.add(AddDistanceToRoutes())

    // Register controllers
    try app.register(
        collection: UserController(
            authRateLimiterMiddleware: AuthRateLimiterMiddleware(
                store: app.authRateLimiterStore,
                maxAttempts: authRateLimitMaxAttempts,
                window: authRateLimitWindow,
                blockDuration: authRateLimitBlockDuration
            )
        )
    )
    try app.register(collection: RouteController())

    await app.jwt.keys.add(hmac: .init(from: jwtSecretData), digestAlgorithm: .sha256)

    try routes(app)

    if autoMigrateOnStartup {
        try await app.autoMigrate()
    } else {
        app.logger.notice("AUTO_MIGRATE is disabled. Skipping automatic migrations on startup.")
    }
}

private func requireEnvironment(_ name: String, allowTestingDefault: Bool = false) throws -> String {
    if allowTestingDefault {
        return Environment.get(name)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? Environment.get(name)!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "test-secret"
    }

    guard let value = Environment.get(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        throw AppConfigurationError(message: "Missing required environment variable: \(name)")
    }

    return value
}

private func data(for value: String, variableName: String) throws -> Data {
    guard let data = value.data(using: .utf8), !data.isEmpty else {
        throw AppConfigurationError(message: "\(variableName) is invalid")
    }

    return data
}

private func boolEnvironment(_ name: String) -> Bool? {
    guard let raw = Environment.get(name)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return nil
    }

    switch raw {
    case "1", "true", "yes", "y", "on":
        return true
    case "0", "false", "no", "n", "off":
        return false
    default:
        return nil
    }
}

private func doubleEnvironment(_ name: String) -> Double? {
    guard let raw = Environment.get(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return nil
    }

    return Double(raw)
}

private func intEnvironment(_ name: String) -> Int? {
    guard let raw = Environment.get(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return nil
    }

    return Int(raw)
}

private func csvEnvironment(_ name: String) -> [String] {
    guard let raw = Environment.get(name), !raw.isEmpty else {
        return []
    }

    return raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func redisConfiguration(from redisURL: String) throws -> RedisConfiguration {
    let tlsConfiguration: TLSConfiguration? = redisURL.lowercased().hasPrefix("rediss://")
        ? TLSConfiguration.makeClientConfiguration()
        : nil

    return try RedisConfiguration(url: redisURL, tlsConfiguration: tlsConfiguration)
}

private func emailProviderEnvironment(_ name: String) -> Application.EmailConfiguration.EmailProvider? {
    guard let raw = Environment.get(name)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !raw.isEmpty else {
        return nil
    }

    return Application.EmailConfiguration.EmailProvider(rawValue: raw)
}

private func validateEmailConfiguration(
    provider: Application.EmailConfiguration.EmailProvider,
    apiKey: String?,
    fromAddress: String?
) throws {
    switch provider {
    case .logger:
        return
    case .resend:
        guard let apiKey, !apiKey.isEmpty else {
            throw AppConfigurationError(message: "EMAIL_API_KEY is required when EMAIL_PROVIDER=resend")
        }
        guard let fromAddress, !fromAddress.isEmpty else {
            throw AppConfigurationError(message: "EMAIL_FROM_ADDRESS is required when EMAIL_PROVIDER=resend")
        }
    }
}

private func configureMiddleware(_ app: Application) throws {
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(SecurityHeadersMiddleware(enableHSTS: app.appConfiguration.enableHSTS))

    if !app.appConfiguration.corsAllowedOrigins.isEmpty {
        let allowedOrigins: CORSMiddleware.AllowOriginSetting
        if app.appConfiguration.corsAllowedOrigins.contains("*") {
            allowedOrigins = .all
        } else {
            allowedOrigins = .originBased
        }

        let configuration = CORSMiddleware.Configuration(
            allowedOrigin: allowedOrigins,
            allowedMethods: [.GET, .POST, .DELETE, .OPTIONS],
            allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith],
            allowCredentials: true
        )
        app.middleware.use(CORSMiddleware(configuration: configuration))
    }
}
