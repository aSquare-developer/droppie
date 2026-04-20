import Vapor

struct ResetPasswordRequestDTO: Content, Validatable {
    let token: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("token", as: String.self, is: !.empty, required: true)
        validations.add("password", as: String.self, is: .count(8...128), required: true)
    }
}
