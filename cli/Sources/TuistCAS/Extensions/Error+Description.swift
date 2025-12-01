import Foundation
import OpenAPIRuntime
import TuistServer

extension Error {
    /// Returns a user-friendly error description, with special handling for ClientError and ServerClientAuthenticationError
    func userFriendlyDescription() -> String {
        if let clientError = self as? ClientError,
           let underlyingServerClientError = clientError.underlyingError as? ServerClientAuthenticationError
        {
            return underlyingServerClientError.errorDescription ?? "Unknown error"
        } else if let localizedError = self as? LocalizedError {
            return localizedError.errorDescription ?? localizedError.localizedDescription
        } else {
            return localizedDescription
        }
    }
}
