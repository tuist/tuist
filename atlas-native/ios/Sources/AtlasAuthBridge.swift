import AtlasAuthFFI
import Foundation

struct AtlasAuthenticationError: LocalizedError {
    let kind: String
    let message: String
    var errorDescription: String? { message }
}

enum AtlasAuthBridge {
    static func command(_ value: [String: Any]) async throws -> [String: Any] {
        let input = try json(value)
        let result = try object(await execute(input))
        if let failure = result["error"] as? [String: String] {
            throw AtlasAuthenticationError(kind: failure["kind"] ?? "internal", message: failure["message"] ?? "Sign-in failed.")
        }
        guard let value = result["ok"] as? [String: Any] else { throw invalidResponse() }
        return value
    }

    static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let value = String(data: data, encoding: .utf8) else { throw invalidResponse() }
        return value
    }

    static func object(_ value: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else { throw invalidResponse() }
        return object
    }

    static func invalidResponse() -> AtlasAuthenticationError {
        AtlasAuthenticationError(kind: "invalid_response", message: "The server returned an invalid OAuth response.")
    }

    static func execute(_ input: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try input.withCString { pointer in
                        guard let result = atlas_auth_execute(pointer) else {
                            throw AtlasAuthenticationError(kind: "internal", message: "Could not complete sign-in.")
                        }
                        defer { atlas_auth_free(result) }
                        return String(cString: result)
                    }
                })
            }
        }
    }
}
