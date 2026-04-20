import Vapor

struct ProfileRequestDTO: Content, Validatable {
    let carOwner: String
    let carModel: String
    let carRegnumber: String
    let vehicleUser: String

    static func validations(_ validations: inout Validations) {
        validations.add("carOwner", as: String.self, is: !.empty, required: true)
        validations.add("carModel", as: String.self, is: !.empty, required: true)
        validations.add("carRegnumber", as: String.self, is: !.empty, required: true)
        validations.add("vehicleUser", as: String.self, is: !.empty, required: true)
    }
}
