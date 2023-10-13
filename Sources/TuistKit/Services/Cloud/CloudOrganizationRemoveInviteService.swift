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
            directory: String?
        ) async throws
    }

    final class CloudOrganizationRemoveInviteService: CloudOrganizationRemoveInviteServicing {
        private let cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        init(
            cancelOrganizationRemoveInviteService: CancelOrganizationInviteServicing = CancelOrganizationInviteService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.cancelOrganizationRemoveInviteService = cancelOrganizationRemoveInviteService
            self.cloudURLService = cloudURLService
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
            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)

            try await cancelOrganizationRemoveInviteService.cancelOrganizationInvite(
                organizationName: organizationName,
                email: email,
                serverURL: cloudURL
            )

            logger.info("The invitation for \(email) to the \(organizationName) organization was successfully cancelled.")
        }
    }
#endif
