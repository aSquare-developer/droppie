import Vapor

struct SecurityHeadersMiddleware: AsyncMiddleware {
    let enableHSTS: Bool

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)

        response.headers.replaceOrAdd(name: .xContentTypeOptions, value: "nosniff")
        response.headers.replaceOrAdd(name: .xFrameOptions, value: "DENY")
        response.headers.replaceOrAdd(name: .init("Referrer-Policy"), value: "no-referrer")
        response.headers.replaceOrAdd(name: .init("Permissions-Policy"), value: "camera=(), microphone=(), geolocation=()")
        response.headers.replaceOrAdd(
            name: .contentSecurityPolicy,
            value: "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        )

        if enableHSTS {
            response.headers.replaceOrAdd(name: .strictTransportSecurity, value: "max-age=31536000; includeSubDomains")
        }

        return response
    }
}
