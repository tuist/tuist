@preconcurrency import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import TuistCAS
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistRootDirectoryLocator

struct CacheStartCommandService {
    private let configLoader: ConfigLoading
    private let rootDirectoryLocator: RootDirectoryLocating
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fileSystem: FileSysteming
    
    init(
        configLoader: ConfigLoading = ConfigLoader(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.configLoader = configLoader
        self.rootDirectoryLocator = rootDirectoryLocator
        self.serverEnvironmentService = serverEnvironmentService
        self.fileSystem = fileSystem
    }
     
    func run(
        path: AbsolutePath
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)
        
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: path) else { return }
        let socketPath = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: "cas.sock")
        if try await !fileSystem.exists(socketPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
        }
        
        guard
            let fullHandle = config.fullHandle
        else { fatalError() }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath.relative(to: rootDirectory).pathString),
                transportSecurity: .plaintext
            ),
            services: [
                KeyValueService(
                    fullHandle: fullHandle,
                    serverURL: serverURL
                ),
                CASDBServiceImpl(config: config),
            ]
        )
        
        try await withThrowingDiscardingTaskGroup { group in
            group.addTask {
                try await server.serve()
            }
            
            Logger.current.info("The CAS Proxy is now running.")
        }
    }
}

