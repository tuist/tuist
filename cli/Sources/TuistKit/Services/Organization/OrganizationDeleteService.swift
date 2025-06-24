import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationDeleteServicing {
    func run(
        organizationName: String,
        directory: String?
    ) async throws
}

final class OrganizationDeleteService: OrganizationDeleteServicing {
    private let deleteOrganizationService: DeleteOrganizationServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        deleteOrganizationService: DeleteOrganizationServicing = DeleteOrganizationService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.deleteOrganizationService = deleteOrganizationService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await deleteOrganizationService.deleteOrganization(
            name: organizationName,
            serverURL: serverURL
        )

        Logger.current.info("Tuist organization \(organizationName) was successfully deleted.")
    }
}
