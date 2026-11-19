import Foundation

public enum ServerCacheAccessMode {
    @TaskLocal public static var serverAllowsNetworkCacheAccess: @Sendable (URL) async throws -> Bool = {
        try await ServerReportPublishingMode.discover($0, capability: "network_trusted_cache_access")
    }

    public static func usesNetworkTrust(
        serverURL: URL,
        authenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) async throws -> Bool {
        guard (try? ServerReportPublishingMode.validateDestination(serverURL)) != nil else { return false }
        let token = try await ServerAuthenticationConfig.$current.withValue(.init(
            backgroundRefresh: false,
            optionalAuthentication: false
        )) {
            try await authenticationController.authenticationToken(serverURL: serverURL)
        }
        if let token {
            guard !token.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ServerReportPublishingError.invalidCredentials }
            return false
        }
        return try await serverAllowsNetworkCacheAccess(serverURL)
    }
}
