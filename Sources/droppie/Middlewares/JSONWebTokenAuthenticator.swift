import Vapor

struct JSONWebTokenAuthenticator: AsyncRequestAuthenticator {
    
    /*
     This Function checking is our request contian the token correctly.
     Make sure that the request headers contains the token and the token is not been tampered with.
     */
    func authenticate(request: Vapor.Request) async throws {
            // Проверяем наличие токена в заголовке Authorization
            guard let payload = try? await request.jwt.verify(as: AuthPayload.self) else {
                throw Abort(.unauthorized, reason: "Invalid or missing token")
            }
            
            // Извлекаем ID пользователя из пейлоада
            guard let userId = UUID(uuidString: payload.userId) else {
                throw Abort(.unauthorized, reason: "Invalid user ID")
            }
            
            // Пытаемся найти пользователя в базе данных
            guard let user = try await User.find(userId, on: request.db) else {
                throw Abort(.unauthorized, reason: "User not found")
            }
            
            // Логиним пользователя в системе
            request.auth.login(user)
        }
}
