import Vapor

struct GoogleRoutesService {
    let client: any Client
    let apiKey: String

    func getDirections(from origin: String, to destination: String) async throws -> ClientResponse {
        // Endpoint
        let url = URI(string: "https://routes.googleapis.com/directions/v2:computeRoutes")

        // Request body
        let body = RouteRequest(
            origin: .init(address: origin),
            destination: .init(address: destination),
            travelMode: "DRIVE"
        )

        // Headers
        let headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": "routes.legs.distanceMeters"
        ]

        return try await client.post(url, headers: headers) { req in
            try req.content.encode(body)
        }
    }
}
