import Foundation
import Fluent
import Vapor

final class User: Model, @unchecked Sendable {
    
    static let schema = "users"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "username")
    var username: String
    
    @Field(key: "password")
    var password: String
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(id: UUID? = nil, username: String, password: String) {
        self.id = id
        self.username = username
        self.password = password
    }
}

extension User: Content { }

extension User: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: !.empty, customFailureDescription: "Username cannot be empty.")
        validations.add("password", as: String.self, is: !.empty, customFailureDescription: "Password cannot be empty.")
        
        validations.add(
            "password",
            as: String.self,
            is: .count(8...128),
            customFailureDescription: "Password must be between 8 and 128 characters long."
        )
    }
}

extension User: Authenticatable { }
