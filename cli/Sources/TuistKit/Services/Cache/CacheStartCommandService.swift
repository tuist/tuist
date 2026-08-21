@preconcurrency import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import TuistCAS
import TuistCASAnalytics
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport

struct CacheStartCommandService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let fileSystem: FileSysteming
    private let cacheURLStore: CacheURLStoring

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.fileSystem = fileSystem
    }

    func run(
        fullHandle: String,
        url: String?,
        upload: Bool = true
    ) async throws {
        // Create a cache-specific logger that only outputs to os_log with debug level
        let cacheLogger = Logger(label: "dev.tuist.cache", factory: OSLogHandler.verbose)

        // Run the cache server with the cache-specific logger
        try await Logger.$current.withValue(cacheLogger) {
            let serverURL = try resolveServerURL(url: url)

            // When the daemon is launched without valid credentials (e.g. the user is
            // logged out), exit cleanly instead of erroring out. The LaunchAgent only
            // respawns the daemon on an unsuccessful exit, so returning here prevents
            // launchd from restarting it every ~10 seconds — and creating a new session
            // directory on each attempt — until the user authenticates.
            guard try await serverAuthenticationController.authenticationToken(serverURL: serverURL) != nil else {
                Logger.current.debug(
                    "Not authenticated against \(serverURL.absoluteString). The cache daemon will exit without starting. Authenticate with `tuist auth login` or set TUIST_TOKEN, then re-run `tuist setup cache`."
                )
                return
            }

            let analyticsDatabase = try CASAnalyticsDatabase()
            try await analyticsDatabase.migrate()
            AnalyticsStateController(database: analyticsDatabase)
                .scheduleMaintenance(stateDirectory: Environment.current.stateDirectory)

            let socketPath = Environment.current.cacheSocketPath(for: fullHandle)
            if try await !fileSystem.exists(socketPath.parentDirectory, isDirectory: true) {
                try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
            }

            let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
            try await warmCacheEndpoint(serverURL: serverURL, accountHandle: accountHandle)

            let server = GRPCServer(
                transport: .http2NIOPosix(
                    address: .unixDomainSocket(path: socketPath.pathString),
                    transportSecurity: .plaintext
                ),
                services: [
                    KeyValueService(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        cacheURLStore: cacheURLStore,
                        upload: upload,
                        analyticsDatabase: analyticsDatabase
                    ),
                    CASService(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        cacheURLStore: cacheURLStore,
                        upload: upload,
                        analyticsDatabase: analyticsDatabase
                    ),
                ]
            )

            try await withThrowingDiscardingTaskGroup { group in
                group.addTask {
                    try await server.serve()
                }
            }
        }
    }

    /// Resolves the cache endpoint once at start-up so the first build does not
    /// pay the endpoint latency race.
    ///
    /// Best-effort by design. An account whose cache instance was reclaimed for
    /// inactivity has no endpoint until the server provisions one back, which
    /// this very request is what triggers. Refusing to start the daemon over
    /// that would turn a transient absence into no caching at all for the whole
    /// provisioning window, and in CI into a failed step. The gRPC services
    /// resolve per request and degrade to building locally, and nothing
    /// negative-caches, so they pick the endpoint up on their own once it
    /// appears.
    private func warmCacheEndpoint(serverURL: URL, accountHandle: String?) async throws {
        Logger.current.debug("Warming cache endpoint URL for \(serverURL.absoluteString)")

        do {
            _ = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
        } catch let error as CacheURLStoreError where error.isTransientAbsence {
            Logger.current.debug(
                "No cache endpoint is serving \(serverURL.absoluteString) yet (\(error.localizedDescription)). Starting the cache daemon anyway; it will pick one up once it is available."
            )
        }
    }

    private func resolveServerURL(url: String?) throws -> URL {
        let configURL = url.flatMap { URL(string: $0) }
        return try configURL
            .map { try serverEnvironmentService.url(configServerURL: $0) } ?? serverEnvironmentService.url()
    }
}
