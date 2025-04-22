import Foundation
import Vapor

struct LoginResponseDTO: Content {
    
    let error: Bool
    var reason: String? = nil
    var token: String? = nil
    var userId: UUID? = nil
    
}
