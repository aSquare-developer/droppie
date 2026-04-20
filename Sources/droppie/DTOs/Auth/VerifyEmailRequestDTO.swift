import Vapor

struct VerifyEmailRequestDTO: Content, Validatable {
    let token: String

    static func validations(_ validations: inout Validations) {
        validations.add("token", as: String.self, is: !.empty, required: true)
    }
}
