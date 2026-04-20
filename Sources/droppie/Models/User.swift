import Foundation
import Fluent
import Vapor

final class User: Model, @unchecked Sendable {
    
    static let schema = "users"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "username")
    var username: String

    @OptionalField(key: "email")
    var email: String?
    
    @Field(key: "password")
    var password: String

    @OptionalField(key: "email_verified_at")
    var emailVerifiedAt: Date?

    @OptionalField(key: "email_verification_token_hash")
    var emailVerificationTokenHash: String?

    @OptionalField(key: "email_verification_token_expires_at")
    var emailVerificationTokenExpiresAt: Date?

    @OptionalField(key: "password_reset_token_hash")
    var passwordResetTokenHash: String?

    @OptionalField(key: "password_reset_token_expires_at")
    var passwordResetTokenExpiresAt: Date?

    @OptionalField(key: "email_verification_last_sent_at")
    var emailVerificationLastSentAt: Date?

    @OptionalField(key: "password_reset_last_sent_at")
    var passwordResetLastSentAt: Date?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(
        id: UUID? = nil,
        username: String,
        email: String? = nil,
        password: String,
        emailVerifiedAt: Date? = nil,
        emailVerificationTokenHash: String? = nil,
        emailVerificationTokenExpiresAt: Date? = nil,
        passwordResetTokenHash: String? = nil,
        passwordResetTokenExpiresAt: Date? = nil,
        emailVerificationLastSentAt: Date? = nil,
        passwordResetLastSentAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.password = password
        self.emailVerifiedAt = emailVerifiedAt
        self.emailVerificationTokenHash = emailVerificationTokenHash
        self.emailVerificationTokenExpiresAt = emailVerificationTokenExpiresAt
        self.passwordResetTokenHash = passwordResetTokenHash
        self.passwordResetTokenExpiresAt = passwordResetTokenExpiresAt
        self.emailVerificationLastSentAt = emailVerificationLastSentAt
        self.passwordResetLastSentAt = passwordResetLastSentAt
    }
}

extension User: Content { }

extension User: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: !.empty, customFailureDescription: "Username cannot be empty.")
        validations.add("email", as: String.self, is: .email, customFailureDescription: "Email is invalid.")
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

extension User {
    static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isEmailVerified: Bool {
        self.emailVerifiedAt != nil
    }
}
