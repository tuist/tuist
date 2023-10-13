#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationDeleteServicing {
        func run(
            organizationName: String,
            directory: String?
        ) async throws
    }

    final class CloudOrganizationDeleteService: CloudOrganizationDeleteServicing {
        private let deleteOrganizationService: DeleteOrganizationServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        init(
            deleteOrganizationService: DeleteOrganizationServicing = DeleteOrganizationService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.deleteOrganizationService = deleteOrganizationService
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            organizationName: String,
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

            try await deleteOrganizationService.deleteOrganization(
                name: organizationName,
                serverURL: cloudURL
            )

            logger.info("Cloud organization \(organizationName) was successfully deleted.")
        }
    }
#endif
