import Fluent

struct AddEmailAuthFieldsToUsers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("email", .string)
            .field("email_verified_at", .datetime)
            .field("email_verification_token_hash", .string)
            .field("email_verification_token_expires_at", .datetime)
            .field("password_reset_token_hash", .string)
            .field("password_reset_token_expires_at", .datetime)
            .update()

        try await database.schema("users")
            .unique(on: "email")
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteUnique(on: "email")
            .deleteField("email")
            .deleteField("email_verified_at")
            .deleteField("email_verification_token_hash")
            .deleteField("email_verification_token_expires_at")
            .deleteField("password_reset_token_hash")
            .deleteField("password_reset_token_expires_at")
            .update()
    }
}
