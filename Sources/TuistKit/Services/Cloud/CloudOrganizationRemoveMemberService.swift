#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationRemoveMemberServicing {
        func run(
            organizationName: String,
            username: String,
            serverURL: String?
        ) async throws
    }

    final class CloudOrganizationRemoveMemberService: CloudOrganizationRemoveMemberServicing {
        private let removeOrganizationMemberService: RemoveOrganizationMemberServicing
        private let cloudURLService: CloudURLServicing

        init(
            removeOrganizationMemberService: RemoveOrganizationMemberServicing = RemoveOrganizationMemberService(),
            cloudURLService: CloudURLServicing = CloudURLService()
        ) {
            self.removeOrganizationMemberService = removeOrganizationMemberService
            self.cloudURLService = cloudURLService
        }

        func run(
            organizationName: String,
            username: String,
            serverURL: String?
        ) async throws {
            let cloudURL = try cloudURLService.url(serverURL: serverURL)

            try await removeOrganizationMemberService.removeOrganizationMember(
                organizationName: organizationName,
                username: username,
                serverURL: cloudURL
            )

            logger.info("The member \(username) was successfully removed from the \(organizationName) organization.")
        }
    }
#endif
