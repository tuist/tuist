#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import Foundation
import Path
import TuistCAS
import TuistCASAnalytics
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport

enum CacheBrokerCommandServiceError: Equatable, LocalizedError {
    case brokerBinaryMissing
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .brokerBinaryMissing:
            return "The 'tuist-cas-broker' binary is missing from the Tuist installation."
        case let .execFailed(message):
            return "Failed to launch the cache broker: \(message)"
        }
    }
}

/// Launches the per-machine Rust cache broker (`tuist-cas-broker`). Resolves the
/// kura REAPI endpoint, then hands off via `execv` so launchd manages the broker
/// process directly — there is no idle Swift parent to forward signals through.
struct CacheBrokerCommandService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheURLStore: CacheURLStoring
    private let resourceLocator: ResourceLocating

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        resourceLocator: ResourceLocating = ResourceLocator()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.resourceLocator = resourceLocator
    }

    func run(url: String?, accountHandle: String?) async throws {
        let serverURL = try resolveServerURL(url: url)

        // When launched without credentials (e.g. logged out), exit cleanly so
        // launchd does not respawn the broker every few seconds.
        guard try await serverAuthenticationController.authenticationToken(serverURL: serverURL) != nil else {
            Logger.current.debug(
                "Not authenticated against \(serverURL.absoluteString). The cache broker will exit without starting."
            )
            return
        }

        guard let brokerPath = try await resourceLocator.casBroker() else {
            throw CacheBrokerCommandServiceError.brokerBinaryMissing
        }
        let tuistPath = try await resourceLocator.cliPath()
        let endpoint = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)

        // Hand the broker its config via the environment. The broker fetches and
        // refreshes its bearer itself by shelling out to `tuist auth token`
        // (TUIST_CAS_TUIST_BIN), so no token is written here.
        setenv("TUIST_CAS_REMOTE_GRPC_URL", endpoint.absoluteString, 1)
        setenv("TUIST_CAS_SERVER_URL", serverURL.absoluteString, 1)
        setenv("TUIST_CAS_TUIST_BIN", tuistPath.pathString, 1)
        // The broker records per-node transfer analytics into this db, which the
        // build-report upload ships to the server — the same path and schema the
        // legacy daemon used, so the upload + server pipeline is unchanged.
        let analyticsDatabasePath = Environment.current.stateDirectory
            .appending(component: CASAnalyticsDatabase.databaseName)
        setenv("TUIST_CAS_ANALYTICS_DB", analyticsDatabasePath.pathString, 1)

        Logger.current.debug("Launching cache broker at \(brokerPath.pathString) for endpoint \(endpoint.absoluteString)")

        let arguments: [UnsafeMutablePointer<CChar>?] = [strdup(brokerPath.pathString), nil]
        execv(brokerPath.pathString, arguments)
        // execv only returns on failure.
        throw CacheBrokerCommandServiceError.execFailed(String(cString: strerror(errno)))
    }

    private func resolveServerURL(url: String?) throws -> URL {
        let configURL = url.flatMap { URL(string: $0) }
        return try configURL
            .map { try serverEnvironmentService.url(configServerURL: $0) } ?? serverEnvironmentService.url()
    }
}
