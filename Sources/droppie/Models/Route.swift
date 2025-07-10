import Vapor
import Fluent

final class Route: Model, Content, @unchecked Sendable {
    
    static let schema = "routes"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "origin")
    var origin: String
    
    @Field(key: "destination")
    var destination: String
    
    @Field(key: "date")
    var date: Date
    
    @Field(key: "distance")
    var distance: Double?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, userID: UUID, origin: String, destination: String, date: Date, distance: Double? = nil) {
        self.id = id
        self.$user.id = userID
        self.origin = origin
        self.destination = destination
        self.date = date
        self.distance = distance
    }
    
    // MARK: - Find Route
    static func find(matching dto: RouteRequestDTO, on db: any Database) async throws -> Route? {
        return try await Route.query(on: db)
            .filter(\.$origin == dto.origin)
            .filter(\.$destination == dto.destination)
            .filter(\.$date == dto.date)
            .first()
    }
    
    // MARK: - Create Route
    static func createRoute(from dto: RouteRequestDTO, userId: UUID, db: any Database) async throws {
        let route = Route(
            userID: userId,
            origin: dto.origin,
            destination: dto.destination,
            date: dto.date
        )
        try await route.save(on: db)
    }
    
    // MARK: - Get Last Destination
    static func getLastDestination(for userID: UUID, on db: any Database) async throws -> String? {
        try await Route.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$id, .descending)
            .first()
            .map { $0.destination }
    }
    
    // MARK: - Save Intermediate Route
    static func saveIntermediateRoute(userId: UUID, distance: Double, intermediateRoute: Route, db: any Database) async throws {
        let speedometerEnd = try await RouteList.getLastSpeedometerEnd(for: userId, on: db)
        
        let newRoute = RouteList(
            userID: userId,
            origin: intermediateRoute.origin,
            destination: intermediateRoute.destination,
            description: "Marsruut restorani",
            speedometerStart: speedometerEnd,
            speedometerEnd: speedometerEnd + distance / 1000.0,
            distance: distance,
            date: intermediateRoute.date
        )
        
        try await newRoute.save(on: db)
    }
    
    // MARK: - Get All Routes from database by user id
    static func getAllRoutes(for userID: UUID, on db: any Database) async throws -> [Route] {
        try await Route.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .limit(20)
            .all()
    }
    
    // MARK: - Get Unique key from origin and destination
    static func generateRouteKey(from dto: RouteRequestDTO) -> String {
        let origin = dto.origin.normalizedRouteComponent()
        let destination = dto.destination.normalizedRouteComponent()
        return "\(origin)-\(destination)"
    }
    
}
