import Fluent

struct CreateProfilesTableMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("profiles")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("car_owner", .string)
            .field("car_model", .string)
            .field("car_regnumber", .string)
            .field("vehicle_user", .string)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("profiles").delete()
    }
}
