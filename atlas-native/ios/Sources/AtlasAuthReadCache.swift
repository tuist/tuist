import Foundation
import SwiftUI

enum AtlasReadCache {
    typealias Request = ([String: Any]) async -> Data?

    static func accessDenied(_ error: Error) -> Bool {
        guard let failure = error as? AtlasAuthenticationError else { return false }
        return ["forbidden", "unavailable", "not_found", "sign_in_required", "unauthorized", "rejected"].contains(failure.kind)
    }

    static func scoped(_ request: Request?, operation: String) -> Request? {
        guard let request else { return nil }
        return { action in
            var action = action
            action["operation"] = operation
            return await request(action)
        }
    }

    static func descriptor(operation: String, action: [String: Any]) -> [String: Any]? {
        switch (operation, action["action"] as? String) {
        case ("business", "list") where action["resource"] as? String == "profile":
            return ["surface": "profile"]
        case ("business", "list"):
            return ["surface": "business_list", "resource": action["resource"] ?? "",
                    "page": action["page"] ?? 1, "query": action["query"] ?? "", "filters": action["filters"] ?? [:]]
        case ("business", "show"):
            return ["surface": "business_record", "resource": action["resource"] ?? "", "id": action["id"] ?? ""]
        case ("time_off", "list"):
            return ["surface": "time_off", "requests_page": action["requests_page"] ?? 1,
                    "holidays_page": action["holidays_page"] ?? 1]
        case ("ai_accounts", "list"): return ["surface": "ai_accounts"]
        case ("connections", "list"): return ["surface": "connections"]
        case ("native", "workflows"), ("native", "executions"), ("native", "approvals"):
            let kind = String((action["action"] as? String ?? "").dropLast())
            return ["surface": "automation_list", "kind": kind, "page": action["page"] ?? 1]
        case ("native", "workflow"), ("native", "execution"), ("native", "approval"):
            return ["surface": "automation_record", "kind": action["action"] ?? "", "id": action["id"] ?? ""]
        default: return nil
        }
    }
}

private struct AtlasReadCacheKey: EnvironmentKey {
    static let defaultValue: AtlasReadCache.Request? = nil
}

extension EnvironmentValues {
    var atlasReadCache: AtlasReadCache.Request? {
        get { self[AtlasReadCacheKey.self] }
        set { self[AtlasReadCacheKey.self] = newValue }
    }
}

extension AtlasAuthentication {
    var cachedRead: AtlasReadCache.Request {
        let identity = sessionIdentity
        return { [weak self] action in
            guard let self, self.server != nil, self.sessionIdentity == identity,
                  let operation = action["operation"] as? String,
                  let read = AtlasReadCache.descriptor(operation: operation, action: action) else { return nil }
            do {
                guard let saved = try AtlasSecureStorage.load("session") else { return nil }
                let response = try await AtlasAuthBridge.command([
                    "operation": "read_cache", "session": try AtlasAuthBridge.object(saved),
                    "directory": await AtlasSecureStorage.prepareReadCache(), "request": read, "local": true
                ])
                guard self.sessionIdentity == identity, !Task.isCancelled,
                      let value = response["value"] as? [String: Any] else { return nil }
                return try JSONSerialization.data(withJSONObject: value)
            } catch { return nil } // A disposable cache never prevents a protected refresh.
        }
    }

    func protectedCommand(operation: String, action: [String: Any], session: [String: Any]) async throws -> [String: Any] {
        let identity = sessionIdentity
        let read = AtlasReadCache.descriptor(operation: operation, action: action)
        let mutation = read == nil && (["business", "time_off", "ai_accounts", "connections"].contains(operation) ||
            (operation == "native" && ["run", "control", "decide"].contains(action["action"] as? String ?? "")))
        if mutation { await invalidateReadCache(session) }
        do {
            if let read {
                let response = try await AtlasAuthBridge.command([
                    "operation": "read_cache", "session": session, "request": read, "local": false,
                    "directory": await AtlasSecureStorage.prepareReadCache()
                ])
                guard let value = response["value"] as? [String: Any] else { throw AtlasAuthBridge.invalidResponse() }
                return value
            }
            var request = action
            request["operation"] = operation
            request["session"] = session
            if operation == "native" { request = ["operation": operation, "session": session, "request": action] }
            let response = try await AtlasAuthBridge.command(request)
            if operation == "orbit_session", response["session_rejected"] as? Bool == true {
                throw AtlasAuthenticationError(kind: "sign_in_required", message: "Sign in to Atlas again.")
            }
            if mutation { await invalidateReadCache(session) }
            return response
        } catch {
            // Fence reads that began during the write, even after an uncertain outcome.
            if mutation { await invalidateReadCache(session) }
            if sessionIdentity == identity, let failure = error as? AtlasAuthenticationError,
               ["sign_in_required", "unauthorized", "rejected"].contains(failure.kind) {
                try? await discardSession(removeRegistration: true)
            }
            throw error
        }
    }

    private func invalidateReadCache(_ session: [String: Any]) async {
        _ = try? await AtlasAuthBridge.command([
            "operation": "invalidate_cache", "session": session, "directory": await AtlasSecureStorage.prepareReadCache()
        ])
    }

    func liveRequest(operation: String) -> ([String: Any]) async throws -> Data {
        let open = authenticatedRequest(operation: operation)
        return { action in
            if action["action"] as? String == "open" { return try await open(action) }
            var request = action
            request["operation"] = operation
            guard let input = String(bytes: try JSONSerialization.data(withJSONObject: request), encoding: .utf8) else {
                throw AtlasAuthenticationError(kind: "invalid_request", message: "Could not encode live request.")
            }
            let response = try await AtlasAuthBridge.execute(input)
            let envelope = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
            guard let result = envelope?["ok"] else {
                throw AtlasAuthenticationError(kind: "closed", message: "Live updates are disconnected.")
            }
            return try JSONSerialization.data(withJSONObject: result)
        }
    }

    func authenticatedRequest(operation: String) -> ([String: Any]) async throws -> Data {
        let identity = sessionIdentity
        return { [weak self] action in
            guard let self, self.server != nil, self.sessionIdentity == identity else {
                throw AtlasAuthenticationError(kind: "sign_in_required", message: "Sign in to Atlas again.")
            }
            let localOpen = operation == "orbit_session" && action["action"] as? String == "open"
            let saved = try (localOpen ? AtlasSecureStorage.load("session") : nil)
            let session = if let saved { try AtlasAuthBridge.object(saved) } else { try await self.apiSession(identity: identity) }
            try Task.checkCancellation()
            guard self.sessionIdentity == identity else { throw CancellationError() }
            var request = action
            request["operation"] = operation
            request["session"] = session
            if localOpen { request["cache_directory"] = await AtlasSecureStorage.prepareReadCache() }
            let response: [String: Any]
            do {
                if localOpen {
                    response = try await AtlasAuthBridge.command(request)
                } else {
                    response = try await self.protectedCommand(operation: operation, action: action, session: session)
                }
            } catch {
                guard self.sessionIdentity == identity else { throw CancellationError() }
                throw error
            }
            guard self.sessionIdentity == identity else {
                if ["presence", "orbit_session", "environment"].contains(operation), let connection = response["connection"] as? String {
                    _ = try? await AtlasAuthBridge.command(["operation": operation, "action": "close", "connection": connection])
                }
                throw CancellationError()
            }
            return try JSONSerialization.data(withJSONObject: response)
        }
    }
}
