import Foundation
import Vapor

struct RouteRequestDTO: Codable {
    let origin: String
    let destination: String
    let createdAt: Date
}

