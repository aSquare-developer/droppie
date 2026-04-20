import Fluent
import Vapor
import FluentSQL

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }

    app.get("health", "live") { _ async -> HealthStatusDTO in
        HealthStatusDTO(status: "ok", checks: ["application": "ok"])
    }

    app.get("health", "ready") { req async throws -> Response in
        var checks: [String: String] = [:]
        var status: HTTPStatus = .ok

        do {
            if let sqlDatabase = req.db as? any SQLDatabase {
                _ = try await sqlDatabase.raw("SELECT 1").all()
            } else {
                _ = try await User.query(on: req.db).limit(1).all()
            }
            checks["database"] = "ok"
        } catch {
            req.logger.error("Readiness database check failed: \(error.localizedDescription)")
            checks["database"] = "error"
            status = .serviceUnavailable
        }

        if req.application.appConfiguration.queueProcessingEnabled {
            do {
                _ = try await req.application.redis.ping().get()
                checks["redis"] = "ok"
            } catch {
                req.logger.error("Readiness Redis check failed: \(error.localizedDescription)")
                checks["redis"] = "error"
                status = .serviceUnavailable
            }
        } else {
            checks["redis"] = "disabled"
        }

        return try await HealthStatusDTO(
            status: status == .ok ? "ok" : "degraded",
            checks: checks
        ).encodeResponse(status: status, for: req)
    }
}
