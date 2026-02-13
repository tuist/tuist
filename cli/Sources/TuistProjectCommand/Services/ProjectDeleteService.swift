import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol ProjectDeleteServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

struct ProjectDeleteService: ProjectDeleteServicing {
    private let deleteProjectService: DeleteProjectServicing
    private let getProjectService: GetProjectServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        deleteProjectService: DeleteProjectServicing = DeleteProjectService(),
        getProjectService: GetProjectServicing = GetProjectService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.deleteProjectService = deleteProjectService
        self.getProjectService = getProjectService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let project = try await getProjectService.getProject(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        try await deleteProjectService.deleteProject(
            projectId: project.id,
            serverURL: serverURL
        )

        Logger.current.info("Successfully deleted the \(project.fullName) project.")
    }
}
