import Foundation
import Vapor

struct RouteResponseDTO: Codable, Content {
    let error: Bool
    var reason: String? = nil
}
