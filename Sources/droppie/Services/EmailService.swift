import Vapor

class EmailService: @unchecked Sendable {
    let app: Application

    init(app: Application) {
        self.app = app
    }

    func sendVerificationEmail(to email: String, token: String) async throws {
        let verificationURL = buildAppURL(path: "/verify-email", token: token)
        let subject = "Verify your email"
        let textBody = """
        Welcome to droppie.

        Use this token to verify your email:
        \(token)

        \(verificationURL.map { "Verification link: \($0)" } ?? "")
        """
        let htmlBody = """
        <p>Welcome to droppie.</p>
        <p>Use this token to verify your email:</p>
        <p><strong>\(token)</strong></p>
        \(verificationURL.map { "<p><a href=\"\($0)\">Verify email</a></p>" } ?? "")
        """

        try await send(
            to: email,
            subject: subject,
            textBody: textBody,
            htmlBody: htmlBody,
            tokenForLogging: token,
            tokenLabel: "Verification"
        )
    }

    func sendPasswordResetEmail(to email: String, token: String) async throws {
        let resetURL = buildAppURL(path: "/reset-password", token: token)
        let subject = "Reset your password"
        let textBody = """
        We received a request to reset your password.

        Use this token to reset your password:
        \(token)

        \(resetURL.map { "Reset link: \($0)" } ?? "")
        """
        let htmlBody = """
        <p>We received a request to reset your password.</p>
        <p>Use this token to reset your password:</p>
        <p><strong>\(token)</strong></p>
        \(resetURL.map { "<p><a href=\"\($0)\">Reset password</a></p>" } ?? "")
        """

        try await send(
            to: email,
            subject: subject,
            textBody: textBody,
            htmlBody: htmlBody,
            tokenForLogging: token,
            tokenLabel: "Password reset"
        )
    }

    private func send(
        to email: String,
        subject: String,
        textBody: String,
        htmlBody: String,
        tokenForLogging: String,
        tokenLabel: String
    ) async throws {
        switch app.emailConfiguration.provider {
        case .logger:
            app.logger.notice("\(tokenLabel) token for \(email): \(tokenForLogging)")
        case .resend:
            try await sendWithResend(
                to: email,
                subject: subject,
                textBody: textBody,
                htmlBody: htmlBody
            )
        }
    }

    private func sendWithResend(
        to email: String,
        subject: String,
        textBody: String,
        htmlBody: String
    ) async throws {
        guard let apiKey = app.emailConfiguration.apiKey, !apiKey.isEmpty else {
            throw Abort(.internalServerError, reason: "Email provider API key is not configured.")
        }

        guard let fromEmail = app.emailConfiguration.fromEmail, !fromEmail.isEmpty else {
            throw Abort(.internalServerError, reason: "Email sender address is not configured.")
        }

        let fromName = app.emailConfiguration.fromName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = (fromName?.isEmpty == false) ? "\(fromName!) <\(fromEmail)>" : fromEmail
        let payload = ResendEmailRequest(
            from: from,
            to: [email],
            subject: subject,
            text: textBody,
            html: htmlBody,
            replyTo: app.emailConfiguration.replyToEmail
        )
        let endpoint = normalizedEmailAPIBaseURL().appending(path: "emails")
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(apiKey)")
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: .accept, value: "application/json")

        let response = try await app.client.post(URI(string: endpoint.absoluteString), headers: headers) { request in
            try request.content.encode(payload)
        }

        guard response.status == .ok || response.status == .accepted else {
            let responseBody = response.body.flatMap { buffer in
                String(buffer: buffer)
            } ?? "<empty>"
            app.logger.error("Resend email delivery failed with status \(response.status.code): \(responseBody)")
            throw Abort(.badGateway, reason: "Email provider rejected the message.")
        }
    }

    private func buildAppURL(path: String, token: String) -> String? {
        guard
            let appBaseURL = app.emailConfiguration.appBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !appBaseURL.isEmpty,
            var components = URLComponents(string: appBaseURL)
        else {
            return nil
        }

        components.path = path
        components.queryItems = [
            URLQueryItem(name: "token", value: token)
        ]

        return components.url?.absoluteString
    }

    private func normalizedEmailAPIBaseURL() -> URL {
        let configuredBaseURL = app.emailConfiguration.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedString = configuredBaseURL.hasSuffix("/") ? configuredBaseURL : configuredBaseURL + "/"

        guard let url = URL(string: normalizedString) else {
            fatalError("Invalid email API base URL: \(configuredBaseURL)")
        }

        return url
    }
}

private struct ResendEmailRequest: Content {
    let from: String
    let to: [String]
    let subject: String
    let text: String
    let html: String
    let replyTo: String?

    enum CodingKeys: String, CodingKey {
        case from
        case to
        case subject
        case text
        case html
        case replyTo = "reply_to"
    }
}
