import Vapor

struct RefreshTokenRequestDTO: Content, Validatable {
    let refreshToken: String

    static func validations(_ validations: inout Validations) {
        validations.add("refreshToken", as: String.self, is: !.empty, required: true)
    }
}
