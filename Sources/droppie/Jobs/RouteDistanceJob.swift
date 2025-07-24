import Vapor
import Foundation
import Queues
import Redis

struct RouteDistanceJob: AsyncJob {

    typealias Payload = UUID
    
    func dequeue(_ context: Queues.QueueContext, _ payload: UUID) async throws {
        
        let db = context.application.db
        
        guard let route = try await Route.find(payload, on: db) else {
            throw Abort(.notFound, reason: "Route not found")
        }
        
        // Generate Unqiue Key
        let uniqueRouteKey = Route.generateRouteKey(from: route)
        
        // Transform our Unique key into RedisKey
        let key = RedisKey(uniqueRouteKey)
        
        // Try to check into Redis memory
        if let value = try await context.application.redis.get(key, as: String.self).get() {
            // We get the value from Redis
            context.logger.info("ℹ️ From Redis, we get Value: \(value), for key: \(key)")
            
            if let distance = Float(value) {
                route.distance = distance
                try await route.save(on: db)
                context.logger.info("✅ Route has been successfully updated!")
            } else {
                context.logger.error("⛔️ Failed to convert string value into double value. Value is: \(value)")
            }
            
        } else {
            // We don't get value, and we need to try create it
            
            // Try to Initializing a Google Service Object
            context.logger.info("ℹ️ Create connection with Google Routes API")
            let googleService = GoogleRoutesService(client: context.application.client, apiKey: Constants.googleAPIKey)
            
            // Get Response from google service
            let googleResponse = try await googleService.getDirections(from: route.origin, to: route.destination)
            
            // Try to decode google service response
            let decodeGoogleResponse = try googleResponse.content.decode(GoogleRoutesResponse.self)
            
            // Check google service status
            guard googleResponse.status == .ok else {
                context.logger.error("⛔️ Google API error: \(googleResponse.status)")
                return
            }
            
            // Get distance value
            if let distance = decodeGoogleResponse.routes.first?.legs.first?.distanceMeters {
                context.logger.info("ℹ️ For key: \(uniqueRouteKey), we have value: \(distance)")

                route.distance = Float(distance)
                try await route.save(on: db)
                context.logger.info("✅ Route has been successfully updated!")
                
                let result = context.application.redis.set(key, to: String(distance))
                context.logger.info("✅ Successfully added into Redis key: \(key) with value: \(distance), result: \(result)")
                 
            } else {
                context.logger.warning("⚠️ No route leg found in Google response")
            }
            
        }
        
        
    }

    
}
