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

enum CacheProxyCommandServiceError: Equatable, LocalizedError {
    case proxyBinaryMissing
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .proxyBinaryMissing:
            return "The 'tuist-cas-proxy' binary is missing from the Tuist installation."
        case let .execFailed(message):
            return "Failed to launch the cache proxy: \(message)"
        }
    }
}

/// Launches the per-machine Rust cache proxy (`tuist-cas-proxy`). Resolves the
/// kura REAPI endpoint, then replaces this process with the proxy so launchd
/// manages it directly. There is no idle Swift parent to forward signals through.
struct CacheProxyCommandService {
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
        // launchd does not respawn the proxy every few seconds.
        guard try await serverAuthenticationController.authenticationToken(serverURL: serverURL) != nil else {
            Logger.current.debug(
                "Not authenticated against \(serverURL.absoluteString). The cache proxy will exit without starting."
            )
            return
        }

        guard let proxyPath = try await resourceLocator.casProxy() else {
            throw CacheProxyCommandServiceError.proxyBinaryMissing
        }
        let tuistPath = try await resourceLocator.cliPath()
        let endpoint = try await remoteEndpoint(serverURL: serverURL, accountHandle: accountHandle)

        // Hand the proxy its config via the environment. The proxy fetches and
        // refreshes its bearer itself by shelling out to `tuist auth token`
        // (TUIST_CAS_TUIST_BIN), so no token is written here.
        setenv("TUIST_CAS_REMOTE_GRPC_URL", endpoint?.absoluteString ?? "", 1)
        setenv("TUIST_CAS_SERVER_URL", serverURL.absoluteString, 1)
        setenv("TUIST_CAS_TUIST_BIN", tuistPath.pathString, 1)
        // The proxy records per-node transfer analytics into this db, which the
        // build-report upload ships to the server — the same path and schema the
        // Swift CASAnalyticsDatabase defines, so the upload + server pipeline is unchanged.
        let analyticsDatabasePath = Environment.current.stateDirectory
            .appending(component: CASAnalyticsDatabase.databaseName)
        setenv("TUIST_CAS_ANALYTICS_DB", analyticsDatabasePath.pathString, 1)
        // Create/upgrade the canonical analytics schema before handing off. The
        // Swift CASAnalyticsDatabase owns this schema (the server reads it and
        // its migrate adds any missing columns to an older db), so the proxy
        // only ever inserts into an existing, current-schema table rather than
        // racing to create a divergent one.
        try? await CASAnalyticsDatabase().migrate()

        Logger.current.debug(
            "Launching cache proxy at \(proxyPath.pathString) for endpoint \(endpoint?.absoluteString ?? "(none yet)")"
        )

        try Self.exec(executable: proxyPath.pathString)
    }

    /// Replaces this process with `executable`, which starts with nothing blocked
    /// and every signal at its default action.
    ///
    /// A plain `execv` carries over the calling thread's signal mask and every
    /// ignored signal. This runs on a Swift concurrency thread, which blocks
    /// SIGTERM, so the proxy would ignore the SIGTERM `launchctl bootout` sends
    /// and leave only when launchd kills it at the job's exit timeout. Until then
    /// its label is still in the domain, and `tuist setup cache` cannot bootstrap
    /// the agent that replaces it.
    static func exec(executable: String) throws -> Never {
        #if canImport(Darwin)
            let result = spawnWithDefaultSignals(
                executable: executable,
                arguments: [],
                flags: POSIX_SPAWN_SETEXEC,
                processIdentifier: nil
            )
        #else
            var unblocked = sigset_t()
            sigemptyset(&unblocked)
            pthread_sigmask(SIG_SETMASK, &unblocked, nil)
            for signal in Int32(1) ..< 32 where signal != SIGKILL && signal != SIGSTOP {
                Glibc.signal(signal, SIG_DFL)
            }
            let arguments: [UnsafeMutablePointer<CChar>?] = [strdup(executable), nil]
            execv(executable, arguments)
            let result = errno
        #endif
        throw CacheProxyCommandServiceError.execFailed(String(cString: strerror(result)))
    }

    #if canImport(Darwin)
        /// Starts `executable` as a child process with the signal state `exec` gives the proxy.
        static func spawn(executable: String, arguments: [String]) throws -> pid_t {
            var processIdentifier: pid_t = 0
            let result = spawnWithDefaultSignals(
                executable: executable,
                arguments: arguments,
                flags: 0,
                processIdentifier: &processIdentifier
            )
            guard result == 0 else {
                throw CacheProxyCommandServiceError.execFailed(String(cString: strerror(result)))
            }
            return processIdentifier
        }

        private static func spawnWithDefaultSignals(
            executable: String,
            arguments: [String],
            flags: Int32,
            processIdentifier: UnsafeMutablePointer<pid_t>?
        ) -> Int32 {
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }

            var unblocked = sigset_t()
            sigemptyset(&unblocked)
            posix_spawnattr_setsigmask(&attributes, &unblocked)
            var defaulted = sigset_t()
            sigfillset(&defaulted)
            sigdelset(&defaulted, SIGKILL)
            sigdelset(&defaulted, SIGSTOP)
            posix_spawnattr_setsigdefault(&attributes, &defaulted)
            posix_spawnattr_setflags(&attributes, Int16(flags | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))

            let cArguments = ([executable] + arguments).map { strdup($0) }
            defer { cArguments.forEach { free($0) } }
            return posix_spawn(processIdentifier, executable, nil, &attributes, cArguments + [nil], environ)
        }
    #endif

    /// The endpoint to start the proxy against, or `nil` when the account has none serving yet or the
    /// logged-in account cannot use it.
    ///
    /// An account whose cache is still being prepared has no endpoint, and refusing to start over
    /// that would leave Xcode retrying a socket nobody listens on. The proxy starts local-only
    /// instead and adopts the endpoint once its periodic resolution finds one.
    private func remoteEndpoint(serverURL: URL, accountHandle: String?) async throws -> URL? {
        do {
            return try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
        } catch let error as CacheURLStoreError where error.isTransientAbsence {
            Logger.current.debug(
                "No cache endpoint is serving \(serverURL.absoluteString) yet (\(error.localizedDescription)). Starting the cache proxy without one."
            )
            return nil
        } catch let CacheURLStoreError.forbidden(message) {
            Logger.current.warning("\(message) Starting the cache proxy without a remote cache.")
            return nil
        }
    }

    private func resolveServerURL(url: String?) throws -> URL {
        let configURL = url.flatMap { URL(string: $0) }
        return try configURL
            .map { try serverEnvironmentService.url(configServerURL: $0) } ?? serverEnvironmentService.url()
    }
}
