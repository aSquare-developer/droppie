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
        
        // Test Function for creating first example
        api.get("routes", "generate", use: generateRoutes)
        
        // Delete route
        api.delete("routes", ":route_id", use: delete)
        
    }
    
    func delete(request: Request) async throws -> HTTPStatus {
        
        guard let routeId = request.parameters.get("route_id", as: UUID.self) else {
                throw Abort(.badRequest, reason: "Missing route ID")
        }
        
        guard let route = try await Route.find(routeId, on: request.db) else {
            throw Abort(.notFound, reason: "Route not found")
        }
        
        let user = try request.auth.require(User.self)
        guard route.$user.id == user.id else {
            throw Abort(.forbidden, reason: "Not allowed to delete this route")
        }
        
        try await route.delete(on: request.db)
        
        return .noContent
        
    }
    
    func generateRoutes(request: Request) async throws -> Response {
        // Пример запроса: /routes/generate?month=2&year=2025&currentOdometer=276743.0
        guard
            let month = request.query[Int.self, at: "month"],
            let year = request.query[Int.self, at: "year"],
            var currentOdometer = request.query[Double.self, at: "currentOdometer"]
        else {
            throw Abort(.badRequest, reason: "Missing month or year")
        }
        
        let data = try await Route.fetchRoutes(forMonth: month, year: year, on: request.db)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        var totalDistance = 0.0
        
        // Формируем данные для PDF
        let routesForPDF: [RoutePDFModel] = data.map { route in
            totalDistance += Double((route.distance ?? 0) / 1000)
            
            let description = "\(route.origin) → \(route.destination) (Tellimuse kohaletoimetamine)"
            let start = currentOdometer
            let end = start + Double((route.distance ?? 0) / 1000)
            
            let pdfRoute = RoutePDFModel(
                date: dateFormatter.string(from: route.date),
                description: description,
                startOdometer: String(format: "%.1f", start),
                endOdometer: String(format: "%.1f", end),
                distance: String(format: "%.2f", route.distance! / 1000)
            )
            
            currentOdometer = end
            
            return pdfRoute
        }

        let context: [String: any Encodable] = [
            "companyName": "aSquare OÜ",
            "vehicleUser": "Artur Anissimov",
            "vehicleRegNumber": "981RFD",
            "period": "Märts 2025",
            "routes": routesForPDF,
            "totalDistance": String(format: "%.2f", totalDistance)
        ]

        let pdfData = try await request.application.pdfService.generate(
            fromLeaf: "routes", // TODO: Here in future, we can change document template.
            context: context,
            using: request
        )

            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/pdf")
            headers.add(name: .contentDisposition, value: "inline; filename=\"routes.pdf\"")
            return Response(status: .ok, headers: headers, body: .init(data: pdfData))
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
