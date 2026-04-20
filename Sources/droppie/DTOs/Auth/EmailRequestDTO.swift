import Vapor

struct EmailRequestDTO: Content, Validatable {
    let email: String

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email, required: true)
    }
}
