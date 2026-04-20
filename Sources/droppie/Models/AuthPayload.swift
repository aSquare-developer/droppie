import Foundation
import JWT

struct AuthPayload: JWTPayload {
    
    typealias Payload = AuthPayload

    enum TokenType: String, Codable {
        case access
        case refresh
    }
    
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
        case userId = "uid"
        case tokenType = "typ"
    }
    
    var expiration: ExpirationClaim // Срок действия токена
    var userId: String
    var tokenType: TokenType
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired() // Проверка токена на срок годности :)
    }
}
