import Foundation
import OpenAPIRuntime
import TuistHTTP
import TuistSupport

extension Error {
    /// Returns a user-friendly error description, with special handling for ClientError and ClientAuthenticationError
    func userFriendlyDescription() -> String {
        if let clientError = self as? ClientError,
           let underlyingAuthError = clientError.underlyingError as? ClientAuthenticationError
        {
            return underlyingAuthError.errorDescription ?? "Unknown error"
        } else if let localizedError = self as? LocalizedError {
            return localizedError.errorDescription ?? localizedError.localizedDescription
        } else {
            return localizedDescription
        }
    }
}
