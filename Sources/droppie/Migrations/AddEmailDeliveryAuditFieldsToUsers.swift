import Fluent

struct AddEmailDeliveryAuditFieldsToUsers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("email_verification_last_sent_at", .datetime)
            .update()

        try await database.schema("users")
            .field("password_reset_last_sent_at", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("email_verification_last_sent_at")
            .update()

        try await database.schema("users")
            .deleteField("password_reset_last_sent_at")
            .update()
    }
}
