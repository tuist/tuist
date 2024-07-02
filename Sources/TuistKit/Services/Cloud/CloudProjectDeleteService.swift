import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CloudProjectDeleteServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class CloudProjectDeleteService: CloudProjectDeleteServicing {
    private let deleteProjectService: DeleteProjectServicing
    private let getProjectService: GetProjectServicing
    private let credentialsStore: CloudCredentialsStoring
    private let cloudURLService: CloudURLServicing
    private let configLoader: ConfigLoading

    init(
        deleteProjectService: DeleteProjectServicing = DeleteProjectService(),
        getProjectService: GetProjectServicing = GetProjectService(),
        credentialsStore: CloudCredentialsStoring = CloudCredentialsStore(),
        cloudURLService: CloudURLServicing = CloudURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.deleteProjectService = deleteProjectService
        self.getProjectService = getProjectService
        self.credentialsStore = credentialsStore
        self.cloudURLService = cloudURLService
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
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)

        let project = try await getProjectService.getProject(
            fullHandle: fullHandle,
            serverURL: cloudURL
        )

        try await deleteProjectService.deleteProject(
            projectId: project.id,
            serverURL: cloudURL
        )

        logger.info("Successfully deleted the \(project.fullName) project.")
    }
}
