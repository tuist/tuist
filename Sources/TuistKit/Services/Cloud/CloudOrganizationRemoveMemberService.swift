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
            directory: String?
        ) async throws
    }

    final class CloudOrganizationRemoveMemberService: CloudOrganizationRemoveMemberServicing {
        private let removeOrganizationMemberService: RemoveOrganizationMemberServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading
        
        init(
            removeOrganizationMemberService: RemoveOrganizationMemberServicing = RemoveOrganizationMemberService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.removeOrganizationMemberService = removeOrganizationMemberService
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            organizationName: String,
            username: String,
            directory: String?
        ) async throws {
            let directoryPath: AbsolutePath
            if let directory {
                directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
            } else {
                directoryPath = FileHandler.shared.currentPath
            }
            let config = try self.configLoader.loadConfig(path: directoryPath)
            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)

            try await removeOrganizationMemberService.removeOrganizationMember(
                organizationName: organizationName,
                username: username,
                serverURL: cloudURL
            )

            logger.info("The member \(username) was successfully removed from the \(organizationName) organization.")
        }
    }
#endif
