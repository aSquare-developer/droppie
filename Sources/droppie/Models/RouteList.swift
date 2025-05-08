import Foundation
import Fluent
import Vapor

enum RouteError: Error {
    case noRouteFound
}

final class RouteList: Model, Content, @unchecked Sendable {
    
    static let schema = "routes_list"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "origin")
    var origin: String
    
    @Field(key: "destination")
    var destination: String
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "speedometer_start")
    var speedometerStart: Int
    
    @Field(key: "speedometer_end")
    var speedometerEnd: Int
    
    @Field(key: "distance")
    var distance: Int
    
    @Field(key: "date")
    var date: Date
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: Int? = nil, userID: UUID, origin: String, destination: String, description: String, speedometerStart: Int, speedometerEnd: Int, distance: Int, date: Date) {
        self.id = id
        self.$user.id = userID
        self.origin = origin
        self.destination = destination
        self.description = description
        self.speedometerStart = speedometerStart
        self.speedometerEnd = speedometerEnd
        self.distance = distance
        self.date = date
    }
    
    static func getLastSpeedometerEnd(for userID: UUID, on db: any Database) async throws -> Int {
        guard let route = try await RouteList.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$id, .descending)
            .first()
        else {
            // TODO: Get from User Profile Speedometer Value
            return 0
        }

        return route.speedometerEnd
    }
}
