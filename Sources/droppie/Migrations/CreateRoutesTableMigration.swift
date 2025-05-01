import Foundation
import Fluent

struct CreateRoutesTableMigration: AsyncMigration {
    
    func prepare(on database: any Database) async throws {
        try await database.schema("routes")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id"))
            .field("origin", .string, .required)
            .field("destination", .string, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("routes").delete()
    }
}
