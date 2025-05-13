import Foundation
import Vapor
import Fluent

class RouteController: RouteCollection {
    
    let speedometerStart: Double = 276210.0
    private var intermediateRoute = true
    
    func boot(routes: any RoutesBuilder) throws {
        // /api/users/
        let api = routes.grouped("api", "users").grouped(JSONWebTokenAuthenticator())
        
        // GET: Get Routes
        // /api/users/routes
        api.get("routes", use: index)
        
        // POST: Saving Route
        // /api/users/route
        api.post("route", use: create)
    }
    
    func index(req: Request) async throws -> [RouteList] {
        
        let user = try req.auth.require(User.self)
        
        guard let userId = user.id else {
            throw Abort(.unauthorized)
        }
        
        do {
            let routes = try await RouteList.getAllRoutes(for: userId, on: req.db)
            return routes
        } catch {
            req.logger.error("Error fetching routes for user \(userId): \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: "Unable to fetch routes")
        }
        
    }
    
    func create(req: Request) async throws -> RouteResponseDTO {
        
        // 1. DTO for the request
        let routeRequestDTO = try req.content.decode(RouteRequestDTO.self)
        
        // TODO: Add Redis functionality.
        
        // 2. Get the userId
        let user = try req.auth.require(User.self)
        
        guard let userId = user.id else {
            throw Abort(.unauthorized)
        }
        
        // 3. Validate query
        try RouteRequestDTO.validate(content: req)
        
        // 4. Initializing a Google Service Object
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
                    speedometerEnd: speedometerEnd + Double(distance) / 1000,
                    distance: Double(distance),
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
                    speedometerEnd: speedometerStart + Double(distance) / 1000,
                    distance: Double(distance),
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
                    speedometerEnd: speedometerEnd + Double(distance) / 1000,
                    distance: Double(distance),
                    date: routeRequestDTO.date
                )
                
                try await newRoute.save(on: req.db)
            }
        }
        
        return RouteResponseDTO(error: false)
        
    }

}
