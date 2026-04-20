import Foundation
import Vapor
import Fluent

actor UserController: RouteCollection {
    private let authRateLimiterMiddleware: AuthRateLimiterMiddleware

    init(authRateLimiterMiddleware: AuthRateLimiterMiddleware) {
        self.authRateLimiterMiddleware = authRateLimiterMiddleware
    }
    
    nonisolated func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("api")
        let authProtected = api.grouped(authRateLimiterMiddleware)
        let authenticated = api.grouped(JSONWebTokenAuthenticator())
        
        // /api/register
        authProtected.post("register", use: register)
        // /api/login
        authProtected.post("login", use: login)
        // /api/refresh
        authProtected.post("refresh", use: refresh)
        // /api/verify-email
        authProtected.post("verify-email", use: verifyEmail)
        // /api/verify-email/request
        authProtected.post("verify-email", "request", use: requestEmailVerification)
        // /api/forgot-password
        authProtected.post("forgot-password", use: forgotPassword)
        // /api/reset-password
        authProtected.post("reset-password", use: resetPassword)

        // /api/me
        authenticated.get("me", use: me)
        // /api/users/profile
        authenticated.get("users", "profile", use: getProfile)
        authenticated.put("users", "profile", use: upsertProfile)
    }
    
    func login(req: Request) async throws -> AuthResponseDTO {
        try LoginRequestDTO.validate(content: req)
        let loginRequest = try req.content.decode(LoginRequestDTO.self)
        let normalizedEmail = User.normalizeEmail(loginRequest.email)
        
        guard let existingUser = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first() else {
            return AuthResponseDTO(error: true, reason: "Invalid email or password.")
            }
        
        let result = try await req.password.async.verify(loginRequest.password, created: existingUser.password)
        
        if !result {
            return AuthResponseDTO(error: true, reason: "Invalid email or password.")
        }

        guard existingUser.isEmailVerified else {
            return AuthResponseDTO(error: true, reason: "Email is not verified.", emailVerified: false)
        }

        return try await buildAuthResponse(for: existingUser, on: req)
    }
    
    func register(req: Request) async throws -> RegisterResponseDTO {
        try RegisterRequestDTO.validate(content: req)
        let registerRequest = try req.content.decode(RegisterRequestDTO.self)
        let normalizedEmail = User.normalizeEmail(registerRequest.email)

        if let _ = try await User.query(on: req.db)
            .filter(\.$username == registerRequest.username)
            .first() {
            throw Abort(.conflict, reason: "Username is already taken.")
        }

        if let _ = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first() {
            throw Abort(.conflict, reason: "Email is already registered.")
        }

        let verificationToken = TokenService.generateToken()
        let verificationTokenHash = TokenService.hash(verificationToken)
        let verificationExpiresAt = Date().addingTimeInterval(60 * 60 * 24)

        let user = User(
            username: registerRequest.username,
            email: normalizedEmail,
            password: try await req.password.async.hash(registerRequest.password),
            emailVerifiedAt: nil,
            emailVerificationTokenHash: verificationTokenHash,
            emailVerificationTokenExpiresAt: verificationExpiresAt
        )

        try await user.save(on: req.db)
        req.application.emailService.sendVerificationEmail(to: normalizedEmail, token: verificationToken)
        
        let authResponse = try await buildAuthResponse(for: user, on: req)

        return RegisterResponseDTO(
            error: false,
            accessToken: authResponse.accessToken,
            refreshToken: authResponse.refreshToken,
            token: authResponse.token,
            userId: authResponse.userId,
            emailVerified: false,
            expiresAt: authResponse.expiresAt
        )
    }

    func refresh(req: Request) async throws -> AuthResponseDTO {
        try RefreshTokenRequestDTO.validate(content: req)
        let payload = try req.content.decode(RefreshTokenRequestDTO.self)

        let refreshPayload = try await req.jwt.verify(payload.refreshToken, as: AuthPayload.self)
        guard refreshPayload.tokenType == .refresh else {
            throw Abort(.unauthorized, reason: "Invalid refresh token.")
        }

        guard let userID = UUID(uuidString: refreshPayload.userId),
              let user = try await User.find(userID, on: req.db) else {
            throw Abort(.unauthorized, reason: "User not found.")
        }

        return try await buildAuthResponse(for: user, on: req)
    }

    func requestEmailVerification(req: Request) async throws -> MessageResponseDTO {
        try EmailRequestDTO.validate(content: req)
        let emailRequest = try req.content.decode(EmailRequestDTO.self)
        let normalizedEmail = User.normalizeEmail(emailRequest.email)

        if let user = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first(),
           !user.isEmailVerified {
            let verificationToken = TokenService.generateToken()
            user.emailVerificationTokenHash = TokenService.hash(verificationToken)
            user.emailVerificationTokenExpiresAt = Date().addingTimeInterval(60 * 60 * 24)
            try await user.save(on: req.db)
            req.application.emailService.sendVerificationEmail(to: normalizedEmail, token: verificationToken)
        }

        return MessageResponseDTO(
            error: false,
            message: "If the email exists and is not verified, a verification email has been sent."
        )
    }

    func verifyEmail(req: Request) async throws -> MessageResponseDTO {
        try VerifyEmailRequestDTO.validate(content: req)
        let verifyRequest = try req.content.decode(VerifyEmailRequestDTO.self)
        let tokenHash = TokenService.hash(verifyRequest.token)

        guard let user = try await User.query(on: req.db)
            .filter(\.$emailVerificationTokenHash == tokenHash)
            .first() else {
            throw Abort(.unauthorized, reason: "Invalid verification token.")
        }

        guard let expiresAt = user.emailVerificationTokenExpiresAt, expiresAt > Date() else {
            throw Abort(.unauthorized, reason: "Verification token has expired.")
        }

        user.emailVerifiedAt = Date()
        user.emailVerificationTokenHash = nil
        user.emailVerificationTokenExpiresAt = nil
        try await user.save(on: req.db)

        return MessageResponseDTO(error: false, message: "Email verified successfully.")
    }

    func forgotPassword(req: Request) async throws -> MessageResponseDTO {
        try EmailRequestDTO.validate(content: req)
        let emailRequest = try req.content.decode(EmailRequestDTO.self)
        let normalizedEmail = User.normalizeEmail(emailRequest.email)

        if let user = try await User.query(on: req.db)
            .filter(\.$email == normalizedEmail)
            .first(),
           user.isEmailVerified {
            let resetToken = TokenService.generateToken()
            user.passwordResetTokenHash = TokenService.hash(resetToken)
            user.passwordResetTokenExpiresAt = Date().addingTimeInterval(60 * 30)
            try await user.save(on: req.db)
            req.application.emailService.sendPasswordResetEmail(to: normalizedEmail, token: resetToken)
        }

        return MessageResponseDTO(
            error: false,
            message: "If the email exists and is eligible, a password reset email has been sent."
        )
    }

    func resetPassword(req: Request) async throws -> MessageResponseDTO {
        try ResetPasswordRequestDTO.validate(content: req)
        let resetRequest = try req.content.decode(ResetPasswordRequestDTO.self)
        let tokenHash = TokenService.hash(resetRequest.token)

        guard let user = try await User.query(on: req.db)
            .filter(\.$passwordResetTokenHash == tokenHash)
            .first() else {
            throw Abort(.unauthorized, reason: "Invalid password reset token.")
        }

        guard let expiresAt = user.passwordResetTokenExpiresAt, expiresAt > Date() else {
            throw Abort(.unauthorized, reason: "Password reset token has expired.")
        }

        user.password = try await req.password.async.hash(resetRequest.password)
        user.passwordResetTokenHash = nil
        user.passwordResetTokenExpiresAt = nil
        try await user.save(on: req.db)

        return MessageResponseDTO(error: false, message: "Password has been reset successfully.")
    }

    func me(req: Request) async throws -> CurrentUserResponseDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let profile = try await Profile.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()

        return .init(
            id: userID,
            username: user.username,
            email: user.email,
            emailVerified: user.isEmailVerified,
            emailVerifiedAt: user.emailVerifiedAt,
            createdAt: user.createdAt,
            profile: try profile?.toResponseDTO()
        )
    }

    func getProfile(req: Request) async throws -> ProfileResponseDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        guard let profile = try await Profile.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() else {
            throw Abort(.notFound, reason: "Profile not found.")
        }

        return try profile.toResponseDTO()
    }

    func upsertProfile(req: Request) async throws -> ProfileResponseDTO {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        try ProfileRequestDTO.validate(content: req)
        let profileRequest = try req.content.decode(ProfileRequestDTO.self)

        if let existingProfile = try await Profile.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() {
            existingProfile.update(from: profileRequest)
            try await existingProfile.save(on: req.db)
            return try existingProfile.toResponseDTO()
        }

        let profile = Profile(
            userId: userID,
            carOwner: profileRequest.carOwner,
            carModel: profileRequest.carModel,
            carRegnumber: profileRequest.carRegnumber,
            vehicleUser: profileRequest.vehicleUser
        )
        try await profile.save(on: req.db)
        return try profile.toResponseDTO()
    }

    private func buildAuthResponse(for user: User, on req: Request) async throws -> AuthResponseDTO {
        let userID = try user.requireID()
        let accessExpirationDate = Date().addingTimeInterval(req.application.appConfiguration.jwtAccessTokenLifetime)
        let refreshExpirationDate = Date().addingTimeInterval(req.application.appConfiguration.jwtRefreshTokenLifetime)

        let accessPayload = AuthPayload(
            expiration: .init(value: accessExpirationDate),
            userId: userID.uuidString,
            tokenType: .access
        )
        let refreshPayload = AuthPayload(
            expiration: .init(value: refreshExpirationDate),
            userId: userID.uuidString,
            tokenType: .refresh
        )

        let accessToken = try await req.jwt.sign(accessPayload)
        let refreshToken = try await req.jwt.sign(refreshPayload)

        return .init(
            error: false,
            accessToken: accessToken,
            refreshToken: refreshToken,
            token: accessToken,
            userId: userID,
            emailVerified: user.isEmailVerified,
            expiresAt: accessExpirationDate
        )
    }
}
