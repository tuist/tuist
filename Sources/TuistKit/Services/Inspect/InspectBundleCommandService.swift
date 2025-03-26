import FileSystem
import Foundation
import Path
import Rosalind
import ServiceContextModule
import TuistLoader
import TuistServer

struct InspectBundleCommandService {
    private let fileSystem: FileSysteming
    private let rosalind: Rosalindable
    private let createBundleService: CreateBundleServicing
    private let configLoader: ConfigLoading
    private let serverURLService: ServerURLServicing

    init(
        fileSystem: FileSysteming = FileSystem(),
        rosalind: Rosalindable = Rosalind(),
        createBundleService: CreateBundleServicing = CreateBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverURLService: ServerURLServicing = ServerURLService()
    ) {
        self.fileSystem = fileSystem
        self.rosalind = rosalind
        self.createBundleService = createBundleService
        self.configLoader = configLoader
        self.serverURLService = serverURLService
    }

    func run(
        path: String
    ) async throws {
        let path = try AbsolutePath(
            validating: path,
            relativeTo: try await fileSystem.currentWorkingDirectory()
        )

        let config = try await configLoader
            .loadConfig(path: try await fileSystem.currentWorkingDirectory())

        guard let fullHandle = config.fullHandle else { fatalError() }
        let serverURL = try serverURLService.url(configServerURL: config.url)
        let artifact = try await rosalind.analyze(path: path)
        try await createBundleService.createBundle(
            fullHandle: fullHandle,
            serverURL: serverURL,
            artifact: artifact
        )
        ServiceContext.current?.ui?.success(
            .alert(
                "Uploaded a bundle to the server."
            )
        )
    }
}
