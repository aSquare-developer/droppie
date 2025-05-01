import Foundation
import Vapor
import Fluent

class RouteController: RouteCollection {
    
    func boot(routes: any RoutesBuilder) throws {
        // /api/users/:userId
        let api = routes.grouped("api", "users", ":userId")
        
        // POST: Saving Route
        // /api/users/:userId/route
        api.post("route", use: create)
    }
    
    func create(req: Request) async throws -> RouteResponseDTO {
        
        // Validate query
        try RouteRequestDTO.validate(content: req)
        
        // Get the userId
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.unauthorized)
        }
        
        // DTO for the request
        let routeRequestDTO = try req.content.decode(RouteRequestDTO.self)
        
        // Create Route
        let route = Route(userId: userId, origin: routeRequestDTO.origin, destination: routeRequestDTO.destination, createdAt: routeRequestDTO.createdAt)
        
        // Try to save our route to the database
        try await route.save(on: req.db)
        
        guard let routeResponseDTO = RouteResponseDTO(route) else {
            throw Abort(.internalServerError)
        }
        
        return routeResponseDTO
        
    }
    
}
