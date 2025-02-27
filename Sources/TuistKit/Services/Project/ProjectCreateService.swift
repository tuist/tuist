import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectCreateServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectCreateService: ProjectCreateServicing {
    private let createProjectService: CreateProjectServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        createProjectService: CreateProjectServicing = CreateProjectService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createProjectService = createProjectService
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

        let project = try await createProjectService.createProject(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info("Tuist project \(project.fullName) was successfully created 🎉")
    }
}
