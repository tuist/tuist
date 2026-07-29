import Foundation
import TuistServer

enum AuthTokenServiceError: LocalizedError, Equatable {
    case notAuthenticated(URL)

    var errorDescription: String? {
        switch self {
        case let .notAuthenticated(url):
            return "Not authenticated against \(url.absoluteString). Run `tuist auth login`."
        }
    }
}

/// Resolves the authentication token for a server and prints it to stdout.
///
/// This is a hidden command used by the Xcode compilation-cache proxy
/// (`tuist-cas-plugin`), which is written in Rust and cannot read the keychain
/// itself. It keeps `ServerAuthenticationController` the single source of truth
/// for token resolution, refresh, and cross-process refresh locking.
public struct AuthTokenService {
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let serverEnvironmentService: ServerEnvironmentServicing

    public init(
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.serverEnvironmentService = serverEnvironmentService
    }

    public func run(serverURL: String?) async throws {
        let url = serverURL.flatMap { URL(string: $0) } ?? serverEnvironmentService.url()
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: url,
            refreshIfNeeded: true
        ) else {
            throw AuthTokenServiceError.notAuthenticated(url)
        }
        // Print only the bearer so the caller can capture it from stdout.
        print(token.value)
    }
}
