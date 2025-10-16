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

enum CacheStartCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        }
    }
}

struct CacheStartCommandService {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fileSystem: FileSysteming

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fileSystem = fileSystem
    }

    func run(
        path: AbsolutePath
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else {
            throw CacheStartCommandServiceError.missingFullHandle
        }
        let socketPath = Environment.current.stateDirectory
            .appending(component: "\(fullHandle.replacingOccurrences(of: "/", with: "_")).sock")
        if try await !fileSystem.exists(socketPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let casWorkerURL = try serverEnvironmentService.casURL(configServerURL: config.casURL ?? serverURL)

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
                    serverURL: serverURL,
                    casWorkerURL: casWorkerURL
                ),
            ]
        )

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask {
                try await server.serve()
            }

            Logger.current.info("The cache server is now running.")
        }
    }
}
