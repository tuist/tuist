#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationCreateServicing {
        func run(
            organizationName: String,
            directory: String?
        ) async throws
    }

    final class CloudOrganizationCreateService: CloudOrganizationCreateServicing {
        private let createOrganizationService: CreateOrganizationServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        init(
            createOrganizationService: CreateOrganizationServicing = CreateOrganizationService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.createOrganizationService = createOrganizationService
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

            let organization = try await createOrganizationService.createOrganization(
                name: organizationName,
                serverURL: cloudURL
            )

            logger.info("Cloud organization \(organization.name) was successfully created 🎉")
        }
    }
#endif
