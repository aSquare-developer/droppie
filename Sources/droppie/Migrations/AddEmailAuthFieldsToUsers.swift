import Fluent
import FluentSQL

struct AddEmailAuthFieldsToUsers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("email", .string)
            .update()

        try await database.schema("users")
            .field("email_verified_at", .datetime)
            .update()

        try await database.schema("users")
            .field("email_verification_token_hash", .string)
            .update()

        try await database.schema("users")
            .field("email_verification_token_expires_at", .datetime)
            .update()

        try await database.schema("users")
            .field("password_reset_token_hash", .string)
            .update()

        try await database.schema("users")
            .field("password_reset_token_expires_at", .datetime)
            .update()

        if let sql = database as? any SQLDatabase {
            try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique ON users (email);").run()
        }
    }

    func revert(on database: any Database) async throws {
        if let sql = database as? any SQLDatabase {
            try await sql.raw("DROP INDEX IF EXISTS users_email_unique;").run()
        }

        try await database.schema("users")
            .deleteField("email")
            .deleteField("email_verified_at")
            .deleteField("email_verification_token_hash")
            .deleteField("email_verification_token_expires_at")
            .deleteField("password_reset_token_hash")
            .deleteField("password_reset_token_expires_at")
            .update()
    }
}
