import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudOrganizationDeleteServicing {
    func run(
        organizationName: String,
        serverURL: String?
    ) async throws
}

final class CloudOrganizationDeleteService: CloudOrganizationDeleteServicing {
    private let deleteOrganizationService: DeleteOrganizationServicing
    private let cloudURLService: CloudURLServicing

    init(
        deleteOrganizationService: DeleteOrganizationServicing = DeleteOrganizationService(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.deleteOrganizationService = deleteOrganizationService
        self.cloudURLService = cloudURLService
    }

    func run(
        organizationName: String,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        try await deleteOrganizationService.deleteOrganization(
            name: organizationName,
            serverURL: cloudURL
        )

        logger.info("Cloud organization \(organizationName) was successfully deleted.")
    }
}
