import Foundation
import Vapor

struct RegisterResponseDTO: Content {
    let error: Bool
    var reason: String? = nil
}
