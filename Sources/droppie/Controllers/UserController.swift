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
        let verificationSentAt = Date()

        let user = User(
            username: registerRequest.username,
            email: normalizedEmail,
            password: try await req.password.async.hash(registerRequest.password),
            emailVerifiedAt: nil,
            emailVerificationTokenHash: verificationTokenHash,
            emailVerificationTokenExpiresAt: verificationExpiresAt,
            emailVerificationLastSentAt: verificationSentAt
        )

        try await user.save(on: req.db)
        do {
            try await sendVerificationEmail(to: normalizedEmail, token: verificationToken, using: req)
        } catch {
            try? await user.delete(on: req.db)
            throw error
        }
        
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
            guard canResendVerification(for: user, on: req) else {
                return MessageResponseDTO(
                    error: false,
                    message: "Verification email was sent recently. Please wait before requesting another one."
                )
            }

            let previousTokenHash = user.emailVerificationTokenHash
            let previousExpiresAt = user.emailVerificationTokenExpiresAt
            let previousLastSentAt = user.emailVerificationLastSentAt
            let verificationToken = TokenService.generateToken()
            user.emailVerificationTokenHash = TokenService.hash(verificationToken)
            user.emailVerificationTokenExpiresAt = Date().addingTimeInterval(60 * 60 * 24)
            user.emailVerificationLastSentAt = Date()
            try await user.save(on: req.db)

            do {
                try await sendVerificationEmail(to: normalizedEmail, token: verificationToken, using: req)
            } catch {
                user.emailVerificationTokenHash = previousTokenHash
                user.emailVerificationTokenExpiresAt = previousExpiresAt
                user.emailVerificationLastSentAt = previousLastSentAt
                try? await user.save(on: req.db)
                return MessageResponseDTO(
                    error: false,
                    message: "If the email exists and is not verified, a verification email will be sent if delivery is available."
                )
            }
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
            guard canRequestPasswordReset(for: user, on: req) else {
                return MessageResponseDTO(
                    error: false,
                    message: "Password reset email was sent recently. Please wait before requesting another one."
                )
            }

            let previousTokenHash = user.passwordResetTokenHash
            let previousExpiresAt = user.passwordResetTokenExpiresAt
            let previousLastSentAt = user.passwordResetLastSentAt
            let resetToken = TokenService.generateToken()
            user.passwordResetTokenHash = TokenService.hash(resetToken)
            user.passwordResetTokenExpiresAt = Date().addingTimeInterval(60 * 30)
            user.passwordResetLastSentAt = Date()
            try await user.save(on: req.db)

            do {
                try await sendPasswordResetEmail(to: normalizedEmail, token: resetToken, using: req)
            } catch {
                user.passwordResetTokenHash = previousTokenHash
                user.passwordResetTokenExpiresAt = previousExpiresAt
                user.passwordResetLastSentAt = previousLastSentAt
                try? await user.save(on: req.db)
                return MessageResponseDTO(
                    error: false,
                    message: "If the email exists and is eligible, a password reset email will be sent if delivery is available."
                )
            }
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

    private func canResendVerification(for user: User, on req: Request) -> Bool {
        guard let lastSentAt = user.emailVerificationLastSentAt else {
            return true
        }

        let cooldown = req.application.appConfiguration.emailVerificationResendCooldown
        return cooldown <= 0 || Date().timeIntervalSince(lastSentAt) >= cooldown
    }

    private func canRequestPasswordReset(for user: User, on req: Request) -> Bool {
        guard let lastSentAt = user.passwordResetLastSentAt else {
            return true
        }

        let cooldown = req.application.appConfiguration.passwordResetRequestCooldown
        return cooldown <= 0 || Date().timeIntervalSince(lastSentAt) >= cooldown
    }

    private func sendVerificationEmail(to email: String, token: String, using req: Request) async throws {
        do {
            try await req.application.emailService.sendVerificationEmail(to: email, token: token)
        } catch {
            req.logger.error("Verification email delivery failed for \(email): \(error.localizedDescription)")
            throw Abort(.serviceUnavailable, reason: "Unable to process email delivery at this time.")
        }
    }

    private func sendPasswordResetEmail(to email: String, token: String, using req: Request) async throws {
        do {
            try await req.application.emailService.sendPasswordResetEmail(to: email, token: token)
        } catch {
            req.logger.error("Password reset email delivery failed for \(email): \(error.localizedDescription)")
            throw Abort(.serviceUnavailable, reason: "Unable to process email delivery at this time.")
        }
    }
}
