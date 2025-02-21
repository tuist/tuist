import Foundation
import Path
import ServiceContextModule
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
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        deleteOrganizationService: DeleteOrganizationServicing = DeleteOrganizationService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.deleteOrganizationService = deleteOrganizationService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
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

        try await deleteOrganizationService.deleteOrganization(
            name: organizationName,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info("Tuist organization \(organizationName) was successfully deleted.")
    }
}
