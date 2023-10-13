#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationBillingServicing {
        func run(
            organizationName: String,
            directory: String?
        ) async throws
    }

    final class CloudOrganizationBillingService: CloudOrganizationBillingServicing {
        private let cloudURLService: CloudURLServicing
        private let opener: Opening
        private let configLoader: ConfigLoading

        init(
            cloudURLService: CloudURLServicing = CloudURLService(),
            opener: Opening = Opener(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.cloudURLService = cloudURLService
            self.opener = opener
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
            let config = try self.configLoader.loadConfig(path: directoryPath)
            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
            try opener.open(
                url: cloudURL
                    .appendingPathComponent("organizations")
                    .appendingPathComponent(organizationName)
                    .appendingPathComponent("billing")
                    .appendingPathComponent("plan")
            )
        }
    }
#endif
