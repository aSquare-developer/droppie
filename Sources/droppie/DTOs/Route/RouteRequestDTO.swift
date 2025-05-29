import Vapor

struct RouteRequestDTO: Content {
    let origin: String
    let destination: String
    let date: Date
}

extension RouteRequestDTO: Codable { }

extension RouteRequestDTO: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("origin", as: String.self, is: !.empty, required: true, customFailureDescription: "Origin cannot be empty.")
        validations.add("destination", as: String.self, is: !.empty, required: true, customFailureDescription: "Destination cannot be empty.")
        validations.add("date", as: Date.self, required: true, customFailureDescription: "Created at is invalid. Wrong format.")
    }
}
