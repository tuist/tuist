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
            directory: String?
        ) async throws
    }

    final class CloudOrganizationUpdateMemberService: CloudOrganizationUpdateMemberServicing {
        private let updateOrganizationMemberService: UpdateOrganizationMemberServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        init(
            updateOrganizationMemberService: UpdateOrganizationMemberServicing = UpdateOrganizationMemberService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.updateOrganizationMemberService = updateOrganizationMemberService
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            organizationName: String,
            username: String,
            role: String,
            directory: String?
        ) async throws {
            let directoryPath: AbsolutePath
            if let directory {
                directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
            } else {
                directoryPath = FileHandler.shared.currentPath
            }
            let config = try configLoader.loadConfig(path: directoryPath)

            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
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
