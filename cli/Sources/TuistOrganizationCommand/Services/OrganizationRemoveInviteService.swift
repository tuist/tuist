import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol OrganizationRemoveInviteServicing {
    func run(
        organizationName: String,
        email: String,
        directory: String?
    ) async throws
}

struct OrganizationRemoveInviteService: OrganizationRemoveInviteServicing {
    private let cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing =
            CancelOrganizationInviteService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cancelOrganizationRemoveInviteService = cancelOrganizationRemoveInviteService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        email: String,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await cancelOrganizationRemoveInviteService.cancelOrganizationInvite(
            organizationName: organizationName,
            email: email,
            serverURL: serverURL
        )

        Logger.current
            .info(
                "The invitation for \(email) to the \(organizationName) organization was successfully cancelled."
            )
    }
}
