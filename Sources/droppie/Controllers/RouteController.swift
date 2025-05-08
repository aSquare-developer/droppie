import Foundation
import Vapor
import Fluent

class RouteController: RouteCollection {
    
    let speedometerStart = 276210
    private var intermediateRoute = true
    
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
        
        let googleService = GoogleRoutesService(client: req.client, apiKey: Constants.googleAPIKey)
        
        // TODO: Нужна проверка, есть ли у пользователя последняя поездка. например пользователь новый.
        if let _ = try await Route.getLastDestination(for: userId, on: req.db) {
            intermediateRoute = true
        } else {
            intermediateRoute = false
        }
        
                
        // Create intermediate route
        if intermediateRoute {

            guard let destination = try await Route.getLastDestination(for: userId, on: req.db) else {
                throw Abort(.notFound, reason: "No routes found for this user")
            }
            
            let intermediateRoute = Route(
                userID: userId,
                origin: destination,
                destination: routeRequestDTO.origin,
                date: routeRequestDTO.date)
            

            try await intermediateRoute.save(on: req.db)
            
            let response = try await googleService.getDirections(from: intermediateRoute.origin, to: intermediateRoute.destination)
            let decodedResponse = try response.content.decode(GoogleRoutesResponse.self)
            
            if let distance = decodedResponse.routes.first?.legs.first?.distanceMeters {
                
                let speedometerEnd = try await RouteList.getLastSpeedometerEnd(for: userId, on: req.db)
                
                let newRoute = RouteList(
                    userID: userId,
                    origin: intermediateRoute.origin,
                    destination: intermediateRoute.destination,
                    description: "Marsruut restorani",
                    speedometerStart: speedometerEnd,
                    speedometerEnd: speedometerEnd + Int(distance) / 1000,
                    distance: distance,
                    date: intermediateRoute.date
                )
                
                try await newRoute.save(on: req.db)
            }
        }
        
        // Create Route
        let route = Route(
            userID: userId,
            origin: routeRequestDTO.origin,
            destination: routeRequestDTO.destination,
            date: routeRequestDTO.date)
        
        // Try to save our route to the database
        try await route.save(on: req.db)
        
        let response = try await googleService.getDirections(from: routeRequestDTO.origin, to: routeRequestDTO.destination)
        
        let decodedResponse = try response.content.decode(GoogleRoutesResponse.self)
        
        if let distance = decodedResponse.routes.first?.legs.first?.distanceMeters {
        
            // TODO: Если первая запись, то не может найти значение getLastSpeedometerEnd и кидает ошибку [ WARNING ] droppie.RouteError.noRouteFound
            // TODO: Решение этой проблемы в моделе RouteList
            let speedometerEnd = try await RouteList.getLastSpeedometerEnd(for: userId, on: req.db)
            
            if speedometerEnd == 0 {
                let newRoute = RouteList(
                    userID: userId,
                    origin: routeRequestDTO.origin,
                    destination: routeRequestDTO.destination,
                    description: "Tellimuse kohaletoimetamine kliendile",
                    speedometerStart: speedometerStart,
                    speedometerEnd: speedometerStart + Int(distance) / 1000,
                    distance: distance,
                    date: routeRequestDTO.date
                )
                
                try await newRoute.save(on: req.db)
            } else {
                let newRoute = RouteList(
                    userID: userId,
                    origin: routeRequestDTO.origin,
                    destination: routeRequestDTO.destination,
                    description: "Tellimuse kohaletoimetamine kliendile",
                    speedometerStart: speedometerEnd,
                    speedometerEnd: speedometerEnd + Int(distance) / 1000,
                    distance: distance,
                    date: routeRequestDTO.date
                )
                
                try await newRoute.save(on: req.db)
            }
        }
        
        return RouteResponseDTO(error: false)
        
    }
    
    func createIntermediateRoute(_ req: Request) {
        // TODO: Get that value from User Profile
    }
    
}
