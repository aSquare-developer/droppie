import Vapor

struct RouteRequest: Content {
    struct Address: Content {
        let address: String
    }

    let origin: Address
    let destination: Address
    let travelMode: String
}
