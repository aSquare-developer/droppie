import Foundation
import Vapor

struct ProfileResponseDTO: Content {
    let id: UUID
    let userId: UUID
    let carOwner: String
    let carModel: String
    let carRegnumber: String
    let vehicleUser: String
    let createdAt: Date?
}
