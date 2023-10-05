#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationCreateServicing {
        func run(
            organizationName: String,
            serverURL: String?
        ) async throws
    }

    final class CloudOrganizationCreateService: CloudOrganizationCreateServicing {
        private let createOrganizationService: CreateOrganizationServicing
        private let cloudURLService: CloudURLServicing

        init(
            createOrganizationService: CreateOrganizationServicing = CreateOrganizationService(),
            cloudURLService: CloudURLServicing = CloudURLService()
        ) {
            self.createOrganizationService = createOrganizationService
            self.cloudURLService = cloudURLService
        }

        func run(
            organizationName: String,
            serverURL: String?
        ) async throws {
            let cloudURL = try cloudURLService.url(serverURL: serverURL)

            let organization = try await createOrganizationService.createOrganization(
                name: organizationName,
                serverURL: cloudURL
            )

            logger.info("Cloud organization \(organization.name) was successfully created 🎉")
        }
    }
#endif
