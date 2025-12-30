@preconcurrency import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import TuistCAS
import TuistCore
import TuistLoader
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport

struct CacheStartCommandService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fileSystem: FileSysteming
    private let cacheURLStore: CacheURLStoring

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        fileSystem: FileSysteming = FileSystem(),
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.cacheURLStore = cacheURLStore
        self.fileSystem = fileSystem
    }

    func run(
        fullHandle: String,
        url: String?
    ) async throws {
        // Create a cache-specific logger that only outputs to os_log with debug level
        let cacheLogger = Logger(label: "dev.tuist.cache", factory: OSLogHandler.verbose)

        // Run the cache server with the cache-specific logger
        try await Logger.$current.withValue(cacheLogger) {
            let socketPath = Environment.current.cacheSocketPath(for: fullHandle)
            if try await !fileSystem.exists(socketPath.parentDirectory, isDirectory: true) {
                try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
            }

            let configURL = url.flatMap { URL(string: $0) }
            let serverURL = try configURL
                .map { try serverEnvironmentService.url(configServerURL: $0) } ?? serverEnvironmentService
                .url()

            Logger.current.debug("Warming cache endpoint URL for \(serverURL.absoluteString)")
            let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
            _ = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)

            let server = GRPCServer(
                transport: .http2NIOPosix(
                    address: .unixDomainSocket(path: socketPath.pathString),
                    transportSecurity: .plaintext
                ),
                services: [
                    KeyValueService(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        cacheURLStore: cacheURLStore
                    ),
                    CASService(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        cacheURLStore: cacheURLStore
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
}
