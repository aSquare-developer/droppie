import Vapor

struct HealthStatusDTO: Content {
    let status: String
    let checks: [String: String]
}
