#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationRemoveInviteServicing {
        func run(
            organizationName: String,
            email: String,
            serverURL: String?
        ) async throws
    }

    final class CloudOrganizationRemoveInviteService: CloudOrganizationRemoveInviteServicing {
        private let cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing
        private let cloudURLService: CloudURLServicing

        init(
            cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing = CancelOrganizationInviteService(),
            cloudURLService: CloudURLServicing = CloudURLService()
        ) {
            self.cancelOrganizationRemoveInviteService = cancelOrganizationRemoveInviteService
            self.cloudURLService = cloudURLService
        }

        func run(
            organizationName: String,
            email: String,
            serverURL: String?
        ) async throws {
            let cloudURL = try cloudURLService.url(serverURL: serverURL)

            try await cancelOrganizationRemoveInviteService.cancelOrganizationInvite(
                organizationName: organizationName,
                email: email,
                serverURL: cloudURL
            )

            logger.info("The invitation for \(email) to the \(organizationName) organization was successfully cancelled.")
        }
    }
#endif
