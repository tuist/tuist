#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationUpdateMemberServicing {
        func run(
            organizationName: String,
            username: String,
            role: String,
            serverURL: String?
        ) async throws
    }

    final class CloudOrganizationUpdateMemberService: CloudOrganizationUpdateMemberServicing {
        private let updateOrganizationMemberService: UpdateOrganizationMemberServicing
        private let cloudURLService: CloudURLServicing

        init(
            updateOrganizationMemberService: UpdateOrganizationMemberServicing = UpdateOrganizationMemberService(),
            cloudURLService: CloudURLServicing = CloudURLService()
        ) {
            self.updateOrganizationMemberService = updateOrganizationMemberService
            self.cloudURLService = cloudURLService
        }

        func run(
            organizationName: String,
            username: String,
            role: String,
            serverURL: String?
        ) async throws {
            let cloudURL = try cloudURLService.url(serverURL: serverURL)

            let member = try await updateOrganizationMemberService.updateOrganizationMember(
                organizationName: organizationName,
                username: username,
                role: CloudOrganization.Member.Role(rawValue: role) ?? .user,
                serverURL: cloudURL
            )

            logger.info("The member \(username) role was successfully updated to \(member.role.rawValue).")
        }
    }
#endif
