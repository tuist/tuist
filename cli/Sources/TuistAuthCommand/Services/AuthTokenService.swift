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
    private let getCacheTokenService: GetCacheTokenServicing

    public init(
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        getCacheTokenService: GetCacheTokenServicing = GetCacheTokenService()
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.serverEnvironmentService = serverEnvironmentService
        self.getCacheTokenService = getCacheTokenService
    }

    public func run(serverURL: String?, projectHandle: String? = nil) async throws {
        // Print only the bearer so the caller can capture it from stdout.
        print(try await token(serverURL: serverURL, projectHandle: projectHandle))
    }

    func token(serverURL: String?, projectHandle: String?) async throws -> String {
        let url = serverURL.flatMap { URL(string: $0) } ?? serverEnvironmentService.url()
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: url,
            refreshIfNeeded: true
        ) else {
            throw AuthTokenServiceError.notAuthenticated(url)
        }
        return await cacheToken(for: projectHandle, serverURL: url) ?? token.value
    }

    /// A token a cache node can verify by itself, so authorizing does not cost a
    /// round-trip back here. Nil when no project was named or the server cannot
    /// mint one, leaving the caller with the credential it already had, which
    /// cache nodes still accept.
    private func cacheToken(for projectHandle: String?, serverURL: URL) async -> String? {
        guard let projectHandle else { return nil }
        return try? await getCacheTokenService.getCacheToken(
            serverURL: serverURL,
            projectHandle: projectHandle
        ).token
    }
}
