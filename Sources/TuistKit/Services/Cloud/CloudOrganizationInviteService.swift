import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudOrganizationInviteServicing {
    func run(
        organizationName: String,
        email: String,
        serverURL: String?
    ) async throws
}

final class CloudOrganizationInviteService: CloudOrganizationInviteServicing {
    private let createOrganizationInviteService: CreateOrganizationInviteServicing
    private let cloudURLService: CloudURLServicing

    init(
        createOrganizationInviteService: CreateOrganizationInviteServicing = CreateOrganizationInviteService(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.createOrganizationInviteService = createOrganizationInviteService
        self.cloudURLService = cloudURLService
    }

    func run(
        organizationName: String,
        email: String,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        let invitation = try await createOrganizationInviteService.createOrganizationInvite(
            organizationName: organizationName,
            email: email,
            serverURL: cloudURL
        )

        logger.info("\(invitation.inviteeEmail) was successfully invited to the \(organizationName) organization 🎉")
    }
}
