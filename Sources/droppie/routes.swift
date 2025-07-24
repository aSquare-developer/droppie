import Fluent
import Vapor
import Redis

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
    
    app.get("redis-test") { req async throws -> String in
        
        let value = req.redis.set("my_key2", to: "test")
        
        return "Done! \(value)"
    }
    
    app.get("redis", ":key") { req async throws -> String in
        guard let keyString = req.parameters.get("key") else {
            throw Abort(.badRequest, reason: "Missing key parameter")
        }

        let key = RedisKey(keyString) // <-- создаём RedisKey из строки

        if let value = try await req.redis.get(key, as: String.self).get() {
            return "value: \(value), for key: \(keyString)"
        } else {
            return "no value found for key: \(keyString)"
        }
    }
    
  
}
