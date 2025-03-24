import Foundation
import Path
import ServiceContextModule
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
        let config = try await configLoader.loadConfig(path: directoryPath)

        let serverURL = try serverURLService.url(configServerURL: config.url)
        _ = try await updateOrganizationService.updateOrganization(
            organizationName: organizationName,
            serverURL: serverURL,
            ssoOrganization: nil
        )

        ServiceContext.current?.logger?.info("SSO for \(organizationName) was removed.")
    }
}
