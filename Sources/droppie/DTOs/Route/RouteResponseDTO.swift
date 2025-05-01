import Foundation
import Vapor

struct RouteResponseDTO: Codable, Content {
    var id: UUID
    var origin: String
    var destination: String
}
