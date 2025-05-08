import Vapor
import Fluent

final class Route: Model, Content, @unchecked Sendable {
    
    static let schema = "routes"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "origin")
    var origin: String
    
    @Field(key: "destination")
    var destination: String
    
    @Field(key: "date")
    var date: Date
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() { }
    
    init(id: Int? = nil, userID: UUID, origin: String, destination: String, date: Date) {
        self.id = id
        self.$user.id = userID
        self.origin = origin
        self.destination = destination
        self.date = date
    }
    
    static func getLastDestination(for userID: UUID, on db: any Database) async throws -> String? {
        try await Route.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$id, .descending)
            .first()
            .map { $0.destination }
    }
    

    
}
