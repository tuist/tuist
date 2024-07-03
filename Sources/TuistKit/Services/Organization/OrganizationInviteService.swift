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
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        createOrganizationInviteService: CreateOrganizationInviteServicing = CreateOrganizationInviteService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createOrganizationInviteService = createOrganizationInviteService
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
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try serverURLService.url(configServerURL: config.cloud?.url)

        let invitation = try await createOrganizationInviteService.createOrganizationInvite(
            organizationName: organizationName,
            email: email,
            serverURL: cloudURL
        )

        let invitationURL = cloudURL
            .appendingPathComponent("auth")
            .appendingPathComponent("invitations")
            .appendingPathComponent(invitation.token)

        logger.info("""
        \(invitation.inviteeEmail) was successfully invited to the \(organizationName) organization 🎉

        You can also share with them the invite link directly: \(invitationURL.absoluteString)
        """)
    }
}
