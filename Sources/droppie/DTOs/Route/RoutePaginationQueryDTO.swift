import Vapor

struct RoutePaginationQueryDTO: Content {
    var page: Int?
    var per: Int?
}
