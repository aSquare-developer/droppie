import Fluent
import Vapor

final class RouteList: Model, Content, @unchecked Sendable {
    
    static let schema = "routes_list"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "origin")
    var origin: String
    
    @Field(key: "destination")
    var destination: String
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "speedometer_start")
    var speedometerStart: Double
    
    @Field(key: "speedometer_end")
    var speedometerEnd: Double
    
    @Field(key: "distance")
    var distance: Double
    
    @Field(key: "date")
    var date: Date
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }

    init(id: UUID? = nil, userID: UUID, origin: String, destination: String, description: String, speedometerStart: Double, speedometerEnd: Double, distance: Double, date: Date) {
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
    
    static func getLastSpeedometerEnd(for userID: UUID, on db: any Database) async throws -> Double {
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
