import Foundation
import Vapor

actor AuthRateLimiterStore {
    struct Entry {
        var attempts: [Date]
        var blockedUntil: Date?
    }

    private var entries: [String: Entry] = [:]

    func registerAttempt(
        for key: String,
        now: Date,
        maxAttempts: Int,
        window: TimeInterval,
        blockDuration: TimeInterval
    ) -> Date? {
        var entry = entries[key] ?? Entry(attempts: [], blockedUntil: nil)

        if let blockedUntil = entry.blockedUntil, blockedUntil > now {
            entries[key] = entry
            return blockedUntil
        }

        entry.blockedUntil = nil
        entry.attempts.removeAll { now.timeIntervalSince($0) > window }
        entry.attempts.append(now)

        if entry.attempts.count > maxAttempts {
            let blockedUntil = now.addingTimeInterval(blockDuration)
            entry.blockedUntil = blockedUntil
            entry.attempts.removeAll()
            entries[key] = entry
            return blockedUntil
        }

        entries[key] = entry
        return nil
    }
}

struct AuthRateLimiterMiddleware: AsyncMiddleware {
    let store: AuthRateLimiterStore
    let maxAttempts: Int
    let window: TimeInterval
    let blockDuration: TimeInterval

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let clientKey = resolvedClientIdentifier(from: request)
        let now = Date()

        if let blockedUntil = await store.registerAttempt(
            for: clientKey,
            now: now,
            maxAttempts: maxAttempts,
            window: window,
            blockDuration: blockDuration
        ) {
            let retryAfter = max(Int(ceil(blockedUntil.timeIntervalSince(now))), 1)
            request.logger.warning("Auth rate limit triggered for \(clientKey); retry after \(retryAfter)s.")

            throw Abort(
                .tooManyRequests,
                headers: ["Retry-After": "\(retryAfter)"],
                reason: "Too many authentication attempts. Please try again later."
            )
        }

        return try await next.respond(to: request)
    }

    private func resolvedClientIdentifier(from request: Request) -> String {
        if let forwardedFor = request.headers.first(name: "X-Forwarded-For")?
            .split(separator: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !forwardedFor.isEmpty {
            return forwardedFor
        }

        if let remoteAddress = request.remoteAddress?.ipAddress {
            return remoteAddress
        }

        return "unknown-client"
    }
}
