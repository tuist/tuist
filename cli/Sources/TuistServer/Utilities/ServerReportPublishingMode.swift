import Foundation
import TuistEnvironment

public enum ServerReportPublishingMode {
    public static var enabled: Bool {
        Environment.current.variables["TUIST_NETWORK_TRUSTED_PUBLISHING"] == "true"
    }

    public static func validateDestination(_ url: URL) throws {
        let host = (url.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              !host.isEmpty, url.user == nil, url.password == nil,
              !["tuist.dev", "tuist.io", "cloud.tuist.io", "cloud.tuist.dev"].contains(host),
              !host.hasSuffix(".tuist.dev"), !host.hasSuffix(".tuist.io")
        else { throw ServerReportPublishingError.selfHostedDestinationRequired }
    }

    public static func usesNetworkTrust(
        serverURL: URL,
        authenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) async throws -> Bool {
        guard enabled else { return false }
        // Errors, including corrupt credentials and failed refreshes, never mean signed out.
        if let token = try await authenticationController.authenticationToken(serverURL: serverURL) {
            guard !token.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ServerReportPublishingError.invalidCredentials }
            return false
        }
        try validateDestination(serverURL)
        return true
    }
}

public enum ServerReportPublishingError: LocalizedError, Equatable {
    case selfHostedDestinationRequired
    case invalidCredentials

    public var errorDescription: String? {
        switch self {
        case .selfHostedDestinationRequired:
            "Credential-free publishing requires a configured self-hosted Tuist server URL."
        case .invalidCredentials:
            "Invalid Tuist credentials. Sign in again or explicitly sign out to remove them."
        }
    }
}
