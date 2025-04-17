import Foundation
import JWT

struct AuthPayload: JWTPayload {
    
    typealias Payload = AuthPayload
    
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
        case userId = "uid"
    }
    
    var expiration: ExpirationClaim // Срок действия токена
    var userId: UUID
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired() // Проверка токена на срок годности :)
    }
}
