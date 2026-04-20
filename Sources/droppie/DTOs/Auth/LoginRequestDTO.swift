import Vapor

struct LoginRequestDTO: Content, Validatable {
    let email: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email, required: true)
        validations.add("password", as: String.self, is: !.empty, required: true)
    }
}
