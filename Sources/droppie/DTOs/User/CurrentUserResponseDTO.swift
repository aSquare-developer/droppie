import Foundation
import Vapor

struct CurrentUserResponseDTO: Content {
    let id: UUID
    let username: String
    let email: String?
    let emailVerified: Bool
    let emailVerifiedAt: Date?
    let createdAt: Date?
    let profile: ProfileResponseDTO?
}
