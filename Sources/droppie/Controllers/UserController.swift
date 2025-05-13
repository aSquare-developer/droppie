import Foundation
import Vapor
import Fluent

class UserController: RouteCollection {
    
    func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("api")
        
        // /api/register
        api.post("register", use: register)
        // /api/login
        api.post("login", use: login)
    }
    
    func login(req: Request) async throws -> LoginResponseDTO {
        
        // 1. Decode the Request
        let user = try req.content.decode(User.self)
        
        // 2. Check if the user exists in the database
        guard let existingUser = try await User.query(on: req.db)
            .filter(\.$username == user.username)
            .first() else {
            return LoginResponseDTO(error: true, reason: "Username is not found!")
            }
        
        // 3. Validate the password
        let result = try await req.password.async.verify(user.password, created: existingUser.password)
        
        // 4. Check result
        if !result {
            return LoginResponseDTO(error: true, reason: "Password is incorrect.")
        }
        
        // 5. Generating the token
        let authPayload = try AuthPayload(expiration: .init(value: .distantFuture), userId: existingUser.requireID().uuidString)
        
        // 6. Returning successful data to the client
        return try await LoginResponseDTO(error: false, token: req.jwt.sign(authPayload), userId: existingUser.requireID())
    }
    
    func register(req: Request) async throws -> RegisterResponseDTO {
        
        // 1. Validate the user
        try User.validate(content: req)
        
        // 2. try to decode our req data
        let user = try req.content.decode(User.self)
        
        // 3. Find if the user already exists using the username
        if let _ = try await User.query(on: req.db)
            .filter(\.$username == user.username)
            .first() {
            throw Abort(.conflict, reason: "Username is already taken.")
        }
        
        // 4. Hash the password
        user.password = try await req.password.async.hash(user.password)
        
        // 5. Save the user to database
        try await user.save(on: req.db)
        
        //6. Return data to the client
        return RegisterResponseDTO(error: false)
    }
    
}
