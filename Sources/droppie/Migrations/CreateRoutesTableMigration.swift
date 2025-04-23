import Foundation
import Fluent

struct CreateRoutesTableMigration: AsyncMigration {
    
    func prepare(on database: any Database) async throws {
        try await database.schema("routes")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id"))
            .field("description", .string, .required)
            .field("initial_speedometer_readings", .double)
            .field("final_speedometer_readings", .double)
            .field("distance", .double)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("routes").delete()
    }
}
