import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationInviteServicing {
    func run(
        organizationName: String,
        email: String,
        directory: String?
    ) async throws
}

final class OrganizationInviteService: OrganizationInviteServicing {
    private let createOrganizationInviteService: CreateOrganizationInviteServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        createOrganizationInviteService: CreateOrganizationInviteServicing =
            CreateOrganizationInviteService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createOrganizationInviteService = createOrganizationInviteService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        email: String,
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

        let invitation = try await createOrganizationInviteService.createOrganizationInvite(
            organizationName: organizationName,
            email: email,
            serverURL: serverURL
        )

        let invitationURL =
            serverURL
                .appendingPathComponent("auth")
                .appendingPathComponent("invitations")
                .appendingPathComponent(invitation.token)

        Logger.current.info(
            """
            \(invitation.inviteeEmail) was successfully invited to the \(organizationName) organization 🎉

            You can also share with them the invite link directly: \(invitationURL.absoluteString)
            """
        )
    }
}
