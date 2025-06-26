import Foundation
import Path
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
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        createProjectService: CreateProjectServicing = CreateProjectService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createProjectService = createProjectService
        self.serverEnvironmentService = serverEnvironmentService
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

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let project = try await createProjectService.createProject(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        Logger.current.info("Tuist project \(project.fullName) was successfully created 🎉")
    }
}
