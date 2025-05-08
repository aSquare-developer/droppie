import Vapor

struct GoogleRoutesResponse: Content {
    let routes: [Route]
    
    struct Route: Content {
        let legs: [Leg]
    }

    struct Leg: Content {
        let distanceMeters: Int
    }
}
