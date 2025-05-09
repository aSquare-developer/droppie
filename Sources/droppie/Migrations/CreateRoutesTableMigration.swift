import Fluent

struct CreateRoutesTableMigration: AsyncMigration {
    
    func prepare(on database: any Database) async throws {
        try await database.schema("routes")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("origin", .string, .required)
            .field("destination", .string, .required)
            .field("date", .datetime, .required)
            .field("created_at", .datetime)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("routes").delete()
    }
}
