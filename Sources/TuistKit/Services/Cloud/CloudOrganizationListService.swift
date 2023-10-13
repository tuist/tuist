#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationListServicing {
        func run(
            json: Bool,
            directory: String?
        ) async throws
    }

    final class CloudOrganizationListService: CloudOrganizationListServicing {
        private let listOrganizationsService: ListOrganizationsServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        init(
            listOrganizationsService: ListOrganizationsServicing = ListOrganizationsService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.listOrganizationsService = listOrganizationsService
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            json: Bool,
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

            let organizations = try await listOrganizationsService.listOrganizations(
                serverURL: cloudURL
            )

            if json {
                let json = try organizations.toJSON()
                logger.info(.init(stringLiteral: json.toString(prettyPrint: true)))
                return
            }

            if organizations.isEmpty {
                logger.info("You currently have no Cloud organizations. Create one by running `tuist cloud organization create`.")
                return
            }

            let organizationsString = "Listing all your organizations:\n" + organizations.map { "  • \($0.name)" }
                .joined(separator: "\n")
            logger.info("\(organizationsString)")
        }
    }
#endif
