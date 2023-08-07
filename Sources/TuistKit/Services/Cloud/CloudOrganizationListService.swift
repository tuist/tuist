import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudOrganizationListServicing {
    func run(
        json: Bool,
        serverURL: String?
    ) async throws
}

final class CloudOrganizationListService: CloudOrganizationListServicing {
    private let listOrganizationsService: ListOrganizationsServicing
    private let cloudURLService: CloudURLServicing

    init(
        listOrganizationsService: ListOrganizationsServicing = ListOrganizationsService(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.listOrganizationsService = listOrganizationsService
        self.cloudURLService = cloudURLService
    }

    func run(
        json: Bool,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

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
