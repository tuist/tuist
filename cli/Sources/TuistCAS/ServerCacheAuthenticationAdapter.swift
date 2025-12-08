import Foundation
import TuistCache
import TuistServer

/// Adapter that bridges TuistServer's authentication to TuistCache's authentication protocol.
///
/// This adapter is necessary because TuistCache cannot depend on TuistServer directly
/// (to avoid pulling in heavy dependencies and keep TuistCache's dependency footprint minimal).
/// TuistCAS, which depends on both modules, provides this bridge between them.
public struct ServerCacheAuthenticationAdapter: CacheAuthenticationProviding {
    private let serverAuthenticationController: ServerAuthenticationControlling

    public init(
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) {
        self.serverAuthenticationController = serverAuthenticationController
    }

    public func authenticationToken(serverURL: URL) async throws -> String? {
        try await serverAuthenticationController.authenticationToken(serverURL: serverURL)?.value
    }
}
