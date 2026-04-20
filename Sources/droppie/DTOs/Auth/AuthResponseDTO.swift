import Foundation
import Vapor

struct AuthResponseDTO: Content {
    let error: Bool
    var reason: String? = nil
    var accessToken: String? = nil
    var refreshToken: String? = nil
    var token: String? = nil
    var userId: UUID? = nil
    var emailVerified: Bool? = nil
    var expiresAt: Date? = nil
}
