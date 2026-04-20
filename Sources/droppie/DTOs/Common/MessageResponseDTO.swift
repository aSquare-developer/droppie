import Vapor

struct MessageResponseDTO: Content {
    let error: Bool
    let message: String
}
