import Foundation
import Vapor

extension RouteRequestDTO: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("origin", as: String.self, is: !.empty, required: true, customFailureDescription: "Origin cannot be empty.")
        validations.add("destination", as: String.self, is: !.empty, required: true, customFailureDescription: "Destination cannot be empty.")
        validations.add("createdAt", as: Date.self, required: true, customFailureDescription: "Created at is invalid. Wrong format.")
    }
}
