import Fluent

struct CreateRoutesListTableMigration: AsyncMigration {
    
    func prepare(on database: any Database) async throws {
        try await database.schema("routes_list")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id"))
            .field("origin", .string, .required)
            .field("destination", .string, .required)
            .field("description", .string, .required)
            .field("speedometer_start", .double, .required)
            .field("speedometer_end", .double, .required)
            .field("distance", .double, .required)
            .field("date", .datetime, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("routes_list").delete()
    }
}
