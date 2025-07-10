import Vapor
import Foundation
import Queues
import Redis

struct RouteDistanceJob: AsyncJob {

    typealias Payload = RouteRequestDTO
    
    func dequeue(_ context: Queues.QueueContext, _ payload: RouteRequestDTO) async throws {
        
        // Здесь логика: например, вызов Google API, сохранение в БД и т.п.
        
        // Generate Unqiue Key
        let uniqueRouteKey = Route.generateRouteKey(from: payload)
        
        // Transform our Unique key into RedisKey
        let key = RedisKey(uniqueRouteKey)
        
        // Try to check into Redis memory
        if let value = try await context.application.redis.get(key, as: String.self).get() {
            // We get the value from Redis
            context.logger.info("Value: \(value), for key: \(key)")
        } else {
            // We don't get value, and know we try create it
            
            // Try to Initializing a Google Service Object
            let googleService = GoogleRoutesService(client: context.application.client, apiKey: Constants.googleAPIKey)
            
            // Get Response from google service
            let googleResponse = try await googleService.getDirections(from: payload.origin, to: payload.destination)
            
            // Try to decode google service response
            let decodeGoogleResponse = try googleResponse.content.decode(GoogleRoutesResponse.self)
            
            // Get distance value
            if let distance = decodeGoogleResponse.routes.first?.legs.first?.distanceMeters {
                context.logger.info("For key: \(uniqueRouteKey), we have value: \(distance)")
                
                // TODO: Update distance value for our RouteRequestDTO
                // We need to find in our database row with data from RouteRequestDTO
                // And update the distance field.
                // First example how can resolve it
                
                // Get db connection
                let db = context.application.db
                
                // Try to find our DTO in our database
                if let route = try await Route.find(matching: payload, on: db) {
                    // Update distance value
                    route.distance = Double(distance) / 1000
                    // Update our row in db
                    try await route.save(on: db)
                    
                    // TODO: Save new distance into Redis memory
                    // First example how can resolve it
                    let reuslt = context.application.redis.set(key, to: String(distance))
                } else {
                    context.logger.warning("⚠️ Route not found for given payload")
                    return
                }
                

            } else {
                context.logger.warning("⚠️ No route leg found in Google response")
            }
            
        }
        
        
    }

    
}
