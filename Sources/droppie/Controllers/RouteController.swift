import Vapor
import Fluent

actor RouteController: RouteCollection {
        
    nonisolated func boot(routes: any RoutesBuilder) throws {
        // /api/users/
        let api = routes.grouped("api", "users").grouped(JSONWebTokenAuthenticator())
        
        // GET: Get Routes
        // /api/users/routes
        api.get("routes", use: index)
        
        // POST: Saving Route
        // /api/users/route
        api.post("route", use: create)
        
        // TEST
        api.get("fetch", use: fetchData)
    }
    
    func fetchData(req: Request) async throws -> RouteResponseDTO {
        let user = try req.auth.require(User.self)

        guard let userId = user.id else {
            throw Abort(.unauthorized)
        }

        // Только маршруты без distance
        let routes = try await Route.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$distance == nil)
            .sort(\.$createdAt, .ascending)
            .all()

        for route in routes {
            let id = try route.requireID()
            try await req.queue.dispatch(RouteDistanceJob.self, id)
        }
        
        return RouteResponseDTO(error: false)
    }
    
    func index(req: Request) async throws -> [Route] {
        
        let user = try req.auth.require(User.self)
        
        guard let userId = user.id else {
            throw Abort(.unauthorized)
        }
        
        do {
            let routes = try await Route.getAllRoutes(for: userId, on: req.db)
            return routes
        } catch {
            req.logger.error("Error fetching routes for user \(userId): \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: "Unable to fetch routes")
        }
        
    }
    
    func create(req: Request) async throws -> RouteResponseDTO {
        
        // 1. Get user ID
        let user = try req.auth.require(User.self)
        guard let userID = user.id else {
            throw Abort(.unauthorized)
        }
        
        // 2. Validate request
        try RouteRequestDTO.validate(content: req)
        
        // 3. DTO from the request
        let routeRequest = try req.content.decode(RouteRequestDTO.self)
        
        // 4. Create Route object from request
        let route = Route(userID: userID, origin: routeRequest.origin, destination: routeRequest.destination, date: routeRequest.date)
        
        // 5. Try to save our route into database
        try await route.save(on: req.db)
        
        let routeID = try route.requireID()
        
        // Redis section
        try await req.queue.dispatch(RouteDistanceJob.self, routeID)
        
        // Return response to client
        return RouteResponseDTO(error: false)
    }
    
}
