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
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        updateOrganizationService: UpdateOrganizationServicing = UpdateOrganizationService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.updateOrganizationService = updateOrganizationService
        self.serverEnvironmentService = serverEnvironmentService
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

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        _ = try await updateOrganizationService.updateOrganization(
            organizationName: organizationName,
            serverURL: serverURL,
            ssoOrganization: nil
        )

        Logger.current.info("SSO for \(organizationName) was removed.")
    }
}
