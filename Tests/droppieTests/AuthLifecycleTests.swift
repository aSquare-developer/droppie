import Foundation
import XCTest
import Vapor
import XCTVapor
@testable import droppie

final class CapturingEmailService: EmailService, @unchecked Sendable {
    private(set) var verificationTokensByEmail: [String: String] = [:]
    private(set) var resetTokensByEmail: [String: String] = [:]

    override func sendVerificationEmail(to email: String, token: String) async throws {
        verificationTokensByEmail[email] = token
    }

    override func sendPasswordResetEmail(to email: String, token: String) async throws {
        resetTokensByEmail[email] = token
    }
}

final class FailingEmailService: EmailService, @unchecked Sendable {
    enum StubError: Error {
        case providerRejected
    }

    override func sendVerificationEmail(to email: String, token: String) async throws {
        throw StubError.providerRejected
    }

    override func sendPasswordResetEmail(to email: String, token: String) async throws {
        throw StubError.providerRejected
    }
}

final class AuthLifecycleTests: XCTestCase {
    var app: Application!
    var emailService: CapturingEmailService!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        emailService = CapturingEmailService(app: app)
        app.emailService = emailService
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        emailService = nil
    }

    func testRegisterVerifyLoginAndMeFlow() async throws {
        let registerRequest = RegisterRequestDTO(
            username: "auth_user",
            email: "auth_user@example.com",
            password: "StrongPass123"
        )

        let registerResponse = try await app.sendRequest(
            .POST,
            "/api/register",
            headers: jsonHeaders,
            body: try jsonBody(registerRequest)
        )
        XCTAssertEqual(registerResponse.status, .ok)

        XCTAssertContent(RegisterResponseDTO.self, registerResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.emailVerified, false)
            XCTAssertNotNil(body.accessToken)
            XCTAssertNotNil(body.refreshToken)
            XCTAssertNotNil(body.userId)
        }

        let verificationToken = try XCTUnwrap(emailService.verificationTokensByEmail["auth_user@example.com"])

        let blockedLoginResponse = try await app.sendRequest(
            .POST,
            "/api/login",
            headers: jsonHeaders,
            body: try jsonBody(LoginRequestDTO(email: "auth_user@example.com", password: "StrongPass123"))
        )
        XCTAssertEqual(blockedLoginResponse.status, .ok)
        XCTAssertContent(AuthResponseDTO.self, blockedLoginResponse) { body in
            XCTAssertTrue(body.error)
            XCTAssertEqual(body.emailVerified, false)
            XCTAssertEqual(body.reason, "Email is not verified.")
        }

        let verifyResponse = try await app.sendRequest(
            .POST,
            "/api/verify-email",
            headers: jsonHeaders,
            body: try jsonBody(VerifyEmailRequestDTO(token: verificationToken))
        )
        XCTAssertEqual(verifyResponse.status, .ok)
        XCTAssertContent(MessageResponseDTO.self, verifyResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.message, "Email verified successfully.")
        }

        let loginResponse = try await app.sendRequest(
            .POST,
            "/api/login",
            headers: jsonHeaders,
            body: try jsonBody(LoginRequestDTO(email: "auth_user@example.com", password: "StrongPass123"))
        )
        XCTAssertEqual(loginResponse.status, .ok)

        let auth = try decode(AuthResponseDTO.self, from: loginResponse)
        XCTAssertFalse(auth.error)
        XCTAssertEqual(auth.emailVerified, true)
        let accessToken = try XCTUnwrap(auth.accessToken)

        let meResponse = try await app.sendRequest(
            .GET,
            "/api/me",
            headers: bearerHeaders(token: accessToken)
        )
        XCTAssertEqual(meResponse.status, .ok)
        XCTAssertContent(CurrentUserResponseDTO.self, meResponse) { body in
            XCTAssertEqual(body.username, "auth_user")
            XCTAssertEqual(body.email, "auth_user@example.com")
            XCTAssertTrue(body.emailVerified)
            XCTAssertNotNil(body.emailVerifiedAt)
            XCTAssertNil(body.profile)
        }
    }

    func testRefreshFlowReturnsNewTokenPair() async throws {
        let credentials = try await registerAndVerify(
            username: "refresh_user",
            email: "refresh_user@example.com",
            password: "StrongPass123"
        )

        let refreshResponse = try await app.sendRequest(
            .POST,
            "/api/refresh",
            headers: jsonHeaders,
            body: try jsonBody(RefreshTokenRequestDTO(refreshToken: credentials.refreshToken))
        )
        XCTAssertEqual(refreshResponse.status, .ok)

        XCTAssertContent(AuthResponseDTO.self, refreshResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.emailVerified, true)
            XCTAssertNotNil(body.accessToken)
            XCTAssertNotNil(body.refreshToken)
            XCTAssertNotEqual(body.accessToken, credentials.accessToken)
        }
    }

    func testForgotResetPasswordLifecycle() async throws {
        _ = try await registerAndVerify(
            username: "reset_user",
            email: "reset_user@example.com",
            password: "StrongPass123"
        )

        let forgotResponse = try await app.sendRequest(
            .POST,
            "/api/forgot-password",
            headers: jsonHeaders,
            body: try jsonBody(EmailRequestDTO(email: "reset_user@example.com"))
        )
        XCTAssertEqual(forgotResponse.status, .ok)
        XCTAssertContent(MessageResponseDTO.self, forgotResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.message, "If the email exists and is eligible, a password reset email has been sent.")
        }

        let resetToken = try XCTUnwrap(emailService.resetTokensByEmail["reset_user@example.com"])

        let resetResponse = try await app.sendRequest(
            .POST,
            "/api/reset-password",
            headers: jsonHeaders,
            body: try jsonBody(ResetPasswordRequestDTO(token: resetToken, password: "StrongPass456"))
        )
        XCTAssertEqual(resetResponse.status, .ok)
        XCTAssertContent(MessageResponseDTO.self, resetResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.message, "Password has been reset successfully.")
        }

        let oldLoginResponse = try await app.sendRequest(
            .POST,
            "/api/login",
            headers: jsonHeaders,
            body: try jsonBody(LoginRequestDTO(email: "reset_user@example.com", password: "StrongPass123"))
        )
        XCTAssertEqual(oldLoginResponse.status, .ok)
        XCTAssertContent(AuthResponseDTO.self, oldLoginResponse) { body in
            XCTAssertTrue(body.error)
            XCTAssertEqual(body.reason, "Invalid email or password.")
        }

        let newLoginResponse = try await app.sendRequest(
            .POST,
            "/api/login",
            headers: jsonHeaders,
            body: try jsonBody(LoginRequestDTO(email: "reset_user@example.com", password: "StrongPass456"))
        )
        XCTAssertEqual(newLoginResponse.status, .ok)
        XCTAssertContent(AuthResponseDTO.self, newLoginResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertNotNil(body.accessToken)
            XCTAssertNotNil(body.refreshToken)
        }
    }

    func testEmailVerificationRequestCooldownPreventsImmediateResend() async throws {
        let registerRequest = RegisterRequestDTO(
            username: "cooldown_verify_user",
            email: "cooldown_verify_user@example.com",
            password: "StrongPass123"
        )

        let registerResponse = try await app.sendRequest(
            .POST,
            "/api/register",
            headers: jsonHeaders,
            body: try jsonBody(registerRequest)
        )
        XCTAssertEqual(registerResponse.status, .ok)

        let firstToken = try XCTUnwrap(emailService.verificationTokensByEmail["cooldown_verify_user@example.com"])

        let resendResponse = try await app.sendRequest(
            .POST,
            "/api/verify-email/request",
            headers: jsonHeaders,
            body: try jsonBody(EmailRequestDTO(email: "cooldown_verify_user@example.com"))
        )
        XCTAssertEqual(resendResponse.status, .ok)
        XCTAssertContent(MessageResponseDTO.self, resendResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.message, "Verification email was sent recently. Please wait before requesting another one.")
        }

        XCTAssertEqual(emailService.verificationTokensByEmail["cooldown_verify_user@example.com"], firstToken)
    }

    func testPasswordResetCooldownPreventsImmediateRepeatRequest() async throws {
        _ = try await registerAndVerify(
            username: "cooldown_reset_user",
            email: "cooldown_reset_user@example.com",
            password: "StrongPass123"
        )

        let firstForgotResponse = try await app.sendRequest(
            .POST,
            "/api/forgot-password",
            headers: jsonHeaders,
            body: try jsonBody(EmailRequestDTO(email: "cooldown_reset_user@example.com"))
        )
        XCTAssertEqual(firstForgotResponse.status, .ok)

        let firstToken = try XCTUnwrap(emailService.resetTokensByEmail["cooldown_reset_user@example.com"])

        let secondForgotResponse = try await app.sendRequest(
            .POST,
            "/api/forgot-password",
            headers: jsonHeaders,
            body: try jsonBody(EmailRequestDTO(email: "cooldown_reset_user@example.com"))
        )
        XCTAssertEqual(secondForgotResponse.status, .ok)
        XCTAssertContent(MessageResponseDTO.self, secondForgotResponse) { body in
            XCTAssertFalse(body.error)
            XCTAssertEqual(body.message, "Password reset email was sent recently. Please wait before requesting another one.")
        }

        XCTAssertEqual(emailService.resetTokensByEmail["cooldown_reset_user@example.com"], firstToken)
    }

    func testRegisterMasksSensitiveEmailDeliveryErrors() async throws {
        app.emailService = FailingEmailService(app: app)

        let response = try await app.sendRequest(
            .POST,
            "/api/register",
            headers: jsonHeaders,
            body: try jsonBody(RegisterRequestDTO(
                username: "masked_error_user",
                email: "masked_error_user@example.com",
                password: "StrongPass123"
            ))
        )
        XCTAssertEqual(response.status, .serviceUnavailable)
        XCTAssertContains(response.body.string, "Unable to process email delivery at this time.")
        XCTAssertFalse(response.body.string.contains("providerRejected"))
    }

    func testProfileUpsertAndGetFlow() async throws {
        let credentials = try await registerAndVerify(
            username: "profile_user",
            email: "profile_user@example.com",
            password: "StrongPass123"
        )

        let missingProfileResponse = try await app.sendRequest(
            .GET,
            "/api/users/profile",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(missingProfileResponse.status, .notFound)

        let upsertPayload = ProfileRequestDTO(
            carOwner: "aSquare OU",
            carModel: "Toyota Corolla",
            carRegnumber: "981RFD",
            vehicleUser: "Artur Anissimov"
        )

        let upsertResponse = try await app.sendRequest(
            .PUT,
            "/api/users/profile",
            headers: jsonBearerHeaders(token: credentials.accessToken),
            body: try jsonBody(upsertPayload)
        )
        XCTAssertEqual(upsertResponse.status, .ok)
        XCTAssertContent(ProfileResponseDTO.self, upsertResponse) { body in
            XCTAssertEqual(body.carOwner, "aSquare OU")
            XCTAssertEqual(body.carModel, "Toyota Corolla")
            XCTAssertEqual(body.carRegnumber, "981RFD")
            XCTAssertEqual(body.vehicleUser, "Artur Anissimov")
        }

        let getProfileResponse = try await app.sendRequest(
            .GET,
            "/api/users/profile",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(getProfileResponse.status, .ok)
        XCTAssertContent(ProfileResponseDTO.self, getProfileResponse) { body in
            XCTAssertEqual(body.carOwner, "aSquare OU")
            XCTAssertEqual(body.carModel, "Toyota Corolla")
        }

        let meResponse = try await app.sendRequest(
            .GET,
            "/api/me",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(meResponse.status, .ok)
        XCTAssertContent(CurrentUserResponseDTO.self, meResponse) { body in
            XCTAssertEqual(body.profile?.carModel, "Toyota Corolla")
            XCTAssertEqual(body.profile?.vehicleUser, "Artur Anissimov")
        }
    }

    func testRouteCreateListPaginateAndDeleteFlow() async throws {
        let credentials = try await registerAndVerify(
            username: "routes_user",
            email: "routes_user@example.com",
            password: "StrongPass123"
        )

        let routeOne = RouteRequestDTO(
            origin: "Tallinn",
            destination: "Tartu",
            date: ISO8601DateFormatter().date(from: "2026-04-20T09:00:00Z")!
        )
        let routeTwo = RouteRequestDTO(
            origin: "Tartu",
            destination: "Parnu",
            date: ISO8601DateFormatter().date(from: "2026-04-21T09:00:00Z")!
        )

        let createFirstResponse = try await app.sendRequest(
            .POST,
            "/api/users/route",
            headers: jsonBearerHeaders(token: credentials.accessToken),
            body: try jsonBody(routeOne)
        )
        XCTAssertEqual(createFirstResponse.status, .ok)
        XCTAssertContent(RouteResponseDTO.self, createFirstResponse) { body in
            XCTAssertFalse(body.error)
        }

        let createSecondResponse = try await app.sendRequest(
            .POST,
            "/api/users/route",
            headers: jsonBearerHeaders(token: credentials.accessToken),
            body: try jsonBody(routeTwo)
        )
        XCTAssertEqual(createSecondResponse.status, .ok)

        let firstPageResponse = try await app.sendRequest(
            .GET,
            "/api/users/routes?page=1&per=1",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(firstPageResponse.status, .ok)
        let firstPage = try decode(PaginatedRoutesResponseDTO.self, from: firstPageResponse)
        XCTAssertEqual(firstPage.page, 1)
        XCTAssertEqual(firstPage.per, 1)
        XCTAssertEqual(firstPage.total, 2)
        XCTAssertTrue(firstPage.hasMore)
        XCTAssertEqual(firstPage.items.count, 1)

        let routeIdToDelete = try XCTUnwrap(firstPage.items.first?.id)

        let secondPageResponse = try await app.sendRequest(
            .GET,
            "/api/users/routes?page=2&per=1",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(secondPageResponse.status, .ok)
        let secondPage = try decode(PaginatedRoutesResponseDTO.self, from: secondPageResponse)
        XCTAssertEqual(secondPage.page, 2)
        XCTAssertEqual(secondPage.per, 1)
        XCTAssertEqual(secondPage.total, 2)
        XCTAssertFalse(secondPage.items.isEmpty)

        let deleteResponse = try await app.sendRequest(
            .DELETE,
            "/api/users/route/\(routeIdToDelete.uuidString)",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(deleteResponse.status, .ok)
        XCTAssertContent(RouteResponseDTO.self, deleteResponse) { body in
            XCTAssertFalse(body.error)
        }

        let afterDeleteResponse = try await app.sendRequest(
            .GET,
            "/api/users/routes?page=1&per=10",
            headers: bearerHeaders(token: credentials.accessToken)
        )
        XCTAssertEqual(afterDeleteResponse.status, .ok)
        let afterDelete = try decode(PaginatedRoutesResponseDTO.self, from: afterDeleteResponse)
        XCTAssertEqual(afterDelete.total, 1)
        XCTAssertEqual(afterDelete.items.count, 1)
    }

    func testAuthRateLimitingAfterRepeatedFailedLoginAttempts() async throws {
        for _ in 0..<10 {
            let response = try await app.sendRequest(
                .POST,
                "/api/login",
                headers: jsonHeaders,
                body: try jsonBody(LoginRequestDTO(email: "nobody@example.com", password: "wrong-password"))
            )
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AuthResponseDTO.self, response) { body in
                XCTAssertTrue(body.error)
                XCTAssertEqual(body.reason, "Invalid email or password.")
            }
        }

        let rateLimitedResponse = try await app.sendRequest(
            .POST,
            "/api/login",
            headers: jsonHeaders,
            body: try jsonBody(LoginRequestDTO(email: "nobody@example.com", password: "wrong-password"))
        )
        XCTAssertEqual(rateLimitedResponse.status, .tooManyRequests)
        XCTAssertNotNil(rateLimitedResponse.headers.first(name: .retryAfter))
        XCTAssertContains(rateLimitedResponse.body.string, "Too many authentication attempts")
    }

    private func registerAndVerify(username: String, email: String, password: String) async throws -> (accessToken: String, refreshToken: String) {
        let registerResponse = try await app.sendRequest(
            .POST,
            "/api/register",
            headers: jsonHeaders,
            body: try jsonBody(RegisterRequestDTO(username: username, email: email, password: password))
        )
        XCTAssertEqual(registerResponse.status, .ok)

        let verificationToken = try XCTUnwrap(emailService.verificationTokensByEmail[email])

        let verifyResponse = try await app.sendRequest(
            .POST,
            "/api/verify-email",
            headers: jsonHeaders,
            body: try jsonBody(VerifyEmailRequestDTO(token: verificationToken))
        )
        XCTAssertEqual(verifyResponse.status, .ok)

        let loginResponse = try await app.sendRequest(
            .POST,
            "/api/login",
            headers: jsonHeaders,
            body: try jsonBody(LoginRequestDTO(email: email, password: password))
        )
        XCTAssertEqual(loginResponse.status, .ok)

        let auth = try decode(AuthResponseDTO.self, from: loginResponse)
        return (try XCTUnwrap(auth.accessToken), try XCTUnwrap(auth.refreshToken))
    }

    private var jsonHeaders: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return headers
    }

    private func bearerHeaders(token: String) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(token)")
        return headers
    }

    private func jsonBearerHeaders(token: String) -> HTTPHeaders {
        var headers = jsonHeaders
        headers.add(name: .authorization, value: "Bearer \(token)")
        return headers
    }

    private func jsonBody<T: Encodable>(_ value: T) throws -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return ByteBuffer(data: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: XCTHTTPResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date string: \(value)"
            )
        }
        return try decoder.decode(T.self, from: Data(buffer: response.body))
    }
}
