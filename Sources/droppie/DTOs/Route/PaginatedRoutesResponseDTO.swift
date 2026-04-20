import Vapor

struct PaginatedRoutesResponseDTO: Content {
    let items: [Route]
    let page: Int
    let per: Int
    let total: Int
    let hasMore: Bool
}
