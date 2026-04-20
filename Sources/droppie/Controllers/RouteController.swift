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
        
        // GET: Delete Route
        // /api/users/route/:id
        api.delete("route", ":id", use: delete)
        
    }
    
    func delete(req: Request) async throws -> RouteResponseDTO {
        
        // 1. Get User ID
        let user = try req.auth.require(User.self)
        
        // 2. Get route ID from URL
        guard let routeID = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        // 3. Find route
        guard let route = try await Route.find(routeID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        // 4. Ensure the route belongs to the user
        guard route.$user.id == user.id else {
            throw Abort(.forbidden)
        }
        
        // 5. Delete
        try await route.delete(on: req.db)
        
        return RouteResponseDTO(error: false)
    }
    
    func generateRoutes(request: Request) async throws -> Response {
        // Пример запроса: /routes/generate?month=2&year=2025&currentOdometer=276743.0
        let user = try request.auth.require(User.self)
        guard let userID = user.id else {
            throw Abort(.unauthorized)
        }

        guard
            let month = request.query[Int.self, at: "month"],
            let year = request.query[Int.self, at: "year"],
            var currentOdometer = request.query[Double.self, at: "currentOdometer"]
        else {
            throw Abort(.badRequest, reason: "Missing month or year")
        }

        let data = try await Route.fetchRoutes(for: userID, month: month, year: year, on: request.db)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        let periodFormatter = DateFormatter()
        periodFormatter.locale = Locale(identifier: "et_EE")
        periodFormatter.dateFormat = "LLLL yyyy"

        let periodDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 1))
        let periodLabel = periodDate.map { periodFormatter.string(from: $0).capitalized } ?? "\(month).\(year)"

        var totalDistance = 0.0
        
        // Формируем данные для PDF
        let routesForPDF: [RoutePDFModel] = try data.map { route in
            guard let distance = route.distance else {
                throw Abort(.conflict, reason: "Cannot generate PDF while some routes are still missing distance values.")
            }

            totalDistance += Double(distance / 1000)
            
            let description = "\(route.origin) → \(route.destination) (Tellimuse kohaletoimetamine)"
            let start = currentOdometer
            let end = start + Double(distance / 1000)
            
            let pdfRoute = RoutePDFModel(
                date: dateFormatter.string(from: route.date),
                description: description,
                startOdometer: String(format: "%.1f", start),
                endOdometer: String(format: "%.1f", end),
                distance: String(format: "%.2f", distance / 1000)
            )
            
            currentOdometer = end
            
            return pdfRoute
        }

        let context: [String: any Encodable] = [
            "companyName": "aSquare OÜ",
            "vehicleUser": "Artur Anissimov",
            "vehicleRegNumber": "981RFD",
            "period": periodLabel,
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
    
    func index(req: Request) async throws -> PaginatedRoutesResponseDTO {
        
        let user = try req.auth.require(User.self)
        
        guard let userId = user.id else {
            throw Abort(.unauthorized)
        }

        let pagination = try req.query.decode(RoutePaginationQueryDTO.self)
        let page = pagination.page ?? 1
        let per = pagination.per ?? 20
        
        do {
            let routes = try await Route.getPaginatedRoutes(for: userId, page: page, per: per, on: req.db)
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
        if req.application.appConfiguration.queueProcessingEnabled {
            try await req.queue.dispatch(RouteDistanceJob.self, routeID)
            return RouteResponseDTO(error: false)
        }

        req.logger.warning("Route \(routeID) saved without background distance processing because queue processing is disabled.")
        return RouteResponseDTO(
            error: false,
            reason: "Route saved, but distance calculation is temporarily unavailable."
        )
    }
    
}
