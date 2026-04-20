import Vapor

class EmailService: @unchecked Sendable {
    private let app: Application

    init(app: Application) {
        self.app = app
    }

    func sendVerificationEmail(to email: String, token: String) {
        app.logger.notice("Verification token for \(email): \(token)")
    }

    func sendPasswordResetEmail(to email: String, token: String) {
        app.logger.notice("Password reset token for \(email): \(token)")
    }
}
