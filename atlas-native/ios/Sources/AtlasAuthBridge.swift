import AtlasAuthFFI
import Foundation

struct AtlasAuthenticationError: LocalizedError {
    let kind: String
    let message: String
    var errorDescription: String? { message }
}

enum AtlasAuthBridge {
    static func execute(_ input: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try input.withCString { pointer in
                guard let result = atlas_auth_execute(pointer) else {
                    throw AtlasAuthenticationError(kind: "internal", message: "Could not complete sign-in.")
                }
                defer { atlas_auth_free(result) }
                return String(cString: result)
            }
        }.value
    }
}
