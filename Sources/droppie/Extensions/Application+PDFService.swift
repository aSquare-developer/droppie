//
//  Application+PDFService.swift
//  droppie
//
//  Created by Artur Anissimov on 07.11.2025.
//

import Vapor

extension Application {
    struct AppConfiguration: Sendable {
        let googleRoutesAPIKey: String?
        let queueProcessingEnabled: Bool
        let autoMigrateOnStartup: Bool
        let jwtAccessTokenLifetime: TimeInterval
        let jwtRefreshTokenLifetime: TimeInterval
        let authRateLimitMaxAttempts: Int
        let authRateLimitWindow: TimeInterval
        let authRateLimitBlockDuration: TimeInterval
        let corsAllowedOrigins: [String]
        let enableHSTS: Bool
    }

    private struct PDFServiceKey: StorageKey {
        typealias Value = PDFService
    }

    private struct EmailServiceKey: StorageKey {
        typealias Value = EmailService
    }

    private struct AppConfigurationKey: StorageKey {
        typealias Value = AppConfiguration
    }

    private struct AuthRateLimiterStoreKey: StorageKey {
        typealias Value = AuthRateLimiterStore
    }

    var pdfService: PDFService {
        get {
            if let existing = self.storage[PDFServiceKey.self] {
                return existing
            } else {
                let new = PDFService(app: self)
                self.storage[PDFServiceKey.self] = new
                return new
            }
        }
        set {
            self.storage[PDFServiceKey.self] = newValue
        }
    }

    var emailService: EmailService {
        get {
            if let existing = self.storage[EmailServiceKey.self] {
                return existing
            } else {
                let new = EmailService(app: self)
                self.storage[EmailServiceKey.self] = new
                return new
            }
        }
        set {
            self.storage[EmailServiceKey.self] = newValue
        }
    }

    var appConfiguration: AppConfiguration {
        get {
            guard let configuration = self.storage[AppConfigurationKey.self] else {
                fatalError("Application configuration accessed before setup")
            }
            return configuration
        }
        set {
            self.storage[AppConfigurationKey.self] = newValue
        }
    }

    var authRateLimiterStore: AuthRateLimiterStore {
        get {
            if let existing = self.storage[AuthRateLimiterStoreKey.self] {
                return existing
            }

            let store = AuthRateLimiterStore()
            self.storage[AuthRateLimiterStoreKey.self] = store
            return store
        }
        set {
            self.storage[AuthRateLimiterStoreKey.self] = newValue
        }
    }
}
