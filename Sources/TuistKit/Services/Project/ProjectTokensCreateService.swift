import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectTokensCreateServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectTokensCreateService: ProjectTokensCreateServicing {
    private let createProjectTokenService: CreateProjectTokenServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    convenience init() {
        self.init(
            createProjectTokenService: CreateProjectTokenService(),
            serverURLService: ServerURLService(),
            configLoader: ConfigLoader()
        )
    }

    init(
        createProjectTokenService: CreateProjectTokenServicing,
        serverURLService: ServerURLServicing,
        configLoader: ConfigLoading
    ) {
        self.createProjectTokenService = createProjectTokenService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let token = try await createProjectTokenService.createProjectToken(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info(.init(stringLiteral: token))
    }
}
