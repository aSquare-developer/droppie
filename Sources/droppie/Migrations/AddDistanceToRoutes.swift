import Fluent

struct AddDistanceToRoutes: AsyncMigration {
    
    func prepare(on database: any Database) async throws {
        try await database.schema("routes")
            .field("distance", .double)
            .update()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("routes")
            .deleteField("distance")
            .update()
    }
}
