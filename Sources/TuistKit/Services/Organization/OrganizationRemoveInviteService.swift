import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationRemoveInviteServicing {
    func run(
        organizationName: String,
        email: String,
        directory: String?
    ) async throws
}

final class OrganizationRemoveInviteService: OrganizationRemoveInviteServicing {
    private let cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing = CancelOrganizationInviteService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cancelOrganizationRemoveInviteService = cancelOrganizationRemoveInviteService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        email: String,
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

        try await cancelOrganizationRemoveInviteService.cancelOrganizationInvite(
            organizationName: organizationName,
            email: email,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?
            .info("The invitation for \(email) to the \(organizationName) organization was successfully cancelled.")
    }
}
