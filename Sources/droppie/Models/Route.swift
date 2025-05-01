import Foundation
import Vapor
import Fluent

final class Route: Model, Content, @unchecked Sendable{
    
    static let schema = "routes"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "origin")
    var origin: String
    
    @Field(key: "destination")
    var destination: String
    
    @Field(key: "created_at")
    var createdAt: Date

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() {}
    
    init(id: UUID? = nil, userId: UUID, origin: String, destination: String, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.$user.id = userId
        self.origin = origin
        self.destination = destination
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
}
