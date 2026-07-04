@preconcurrency import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import TuistCache
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
            try analyticsDatabase.migrate()
            AnalyticsStateController(database: analyticsDatabase)
                .scheduleMaintenance(stateDirectory: Environment.current.stateDirectory)

            let socketPath = Environment.current.cacheSocketPath(for: fullHandle)
            if try await !fileSystem.exists(socketPath.parentDirectory, isDirectory: true) {
                try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
            }

            Logger.current.debug("Warming cache endpoint URL for \(serverURL.absoluteString)")
            let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
            _ = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)

            // A key-value response names every artifact the compiler is about
            // to load one by one; prefetching them concurrently as soon as the
            // key resolves takes those loads off the build's critical path.
            let prefetchLoadService = LoadCacheCASService()
            let prefetchAuthenticationController = serverAuthenticationController
            let prefetchCacheURLStore = cacheURLStore
            let prefetcher = CASPrefetcher { casID in
                let cacheURL = try await prefetchCacheURLStore.getCacheURL(
                    for: serverURL,
                    accountHandle: accountHandle
                )
                return try await prefetchLoadService.loadCacheCAS(
                    casId: casID,
                    fullHandle: fullHandle,
                    serverURL: cacheURL,
                    authenticationURL: serverURL,
                    serverAuthenticationController: prefetchAuthenticationController
                )
            }

            // Xcode's CAS plugin client sends HTTP/2 keepalive pings far more
            // frequently than gRPC servers permit by default (gRFC A8 allows
            // one ping per 5 minutes and none without active calls), so the
            // default ping policing repeatedly kills the plugin's connection
            // with GOAWAY "too_many_pings". Every queued CAS operation then
            // stalls until the plugin reconnects, which surfaces as a build
            // that sits idle in bursts. Accept the plugin's ping cadence.
            var transportConfig = HTTP2ServerTransport.Posix.Config.defaults
            transportConfig.connection.keepalive.clientBehavior = .init(
                minPingIntervalWithoutCalls: .seconds(10),
                allowWithoutCalls: true
            )

            let server = GRPCServer(
                transport: .http2NIOPosix(
                    address: .unixDomainSocket(path: socketPath.pathString),
                    transportSecurity: .plaintext,
                    config: transportConfig
                ),
                services: [
                    KeyValueService(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        cacheURLStore: cacheURLStore,
                        upload: upload,
                        analyticsDatabase: analyticsDatabase,
                        prefetcher: prefetcher
                    ),
                    CASService(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        cacheURLStore: cacheURLStore,
                        upload: upload,
                        analyticsDatabase: analyticsDatabase,
                        prefetcher: prefetcher
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

    private func resolveServerURL(url: String?) throws -> URL {
        let configURL = url.flatMap { URL(string: $0) }
        return try configURL
            .map { try serverEnvironmentService.url(configServerURL: $0) } ?? serverEnvironmentService.url()
    }
}
