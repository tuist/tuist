import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectDeleteServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectDeleteService: ProjectDeleteServicing {
    private let deleteProjectService: DeleteProjectServicing
    private let getProjectService: GetProjectServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        deleteProjectService: DeleteProjectServicing = DeleteProjectService(),
        getProjectService: GetProjectServicing = GetProjectService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.deleteProjectService = deleteProjectService
        self.getProjectService = getProjectService
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

        let project = try await getProjectService.getProject(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        try await deleteProjectService.deleteProject(
            projectId: project.id,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info("Successfully deleted the \(project.fullName) project.")
    }
}
