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

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.fileSystem = fileSystem
    }

    func run(
        fullHandle: String,
        url: String?
    ) async throws {
        let socketPath = Environment.current.cacheSocketPath(for: fullHandle)
        if try await !fileSystem.exists(socketPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
        }

        let configURL = url.flatMap { URL(string: $0) }
        let serverURL = try configURL.map { try serverEnvironmentService.url(configServerURL: $0) } ?? serverEnvironmentService
            .url()

        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath.pathString),
                transportSecurity: .plaintext
            ),
            services: [
                KeyValueService(
                    fullHandle: fullHandle,
                    serverURL: serverURL
                ),
                CASService(
                    fullHandle: fullHandle,
                    serverURL: serverURL
                ),
            ]
        )

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask {
                try await server.serve()
            }

            Logger.current.info("The cache server is now running.")
            Logger.current.info("Socket path: \(socketPath.pathString)")
        }
    }
}
