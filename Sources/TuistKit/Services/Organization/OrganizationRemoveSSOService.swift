import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationRemoveSSOServicing {
    func run(
        organizationName: String,
        directory: String?
    ) async throws
}

final class OrganizationRemoveSSOService: OrganizationRemoveSSOServicing {
    private let updateOrganizationService: UpdateOrganizationServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        updateOrganizationService: UpdateOrganizationServicing = UpdateOrganizationService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.updateOrganizationService = updateOrganizationService
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
        let config = try configLoader.loadConfig(path: directoryPath)

        let cloudURL = try serverURLService.url(configServerURL: config.cloud?.url)
        _ = try await updateOrganizationService.updateOrganization(
            organizationName: organizationName,
            serverURL: cloudURL,
            ssoOrganization: nil
        )

        logger.info("SSO for \(organizationName) was removed.")
    }
}
