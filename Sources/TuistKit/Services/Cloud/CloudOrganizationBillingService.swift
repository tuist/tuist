#if canImport(TuistCloud)
import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudOrganizationBillingServicing {
    func run(
        organizationName: String,
        serverURL: String?
    ) async throws
}

final class CloudOrganizationBillingService: CloudOrganizationBillingServicing {
    private let cloudURLService: CloudURLServicing
    private let opener: Opening

    init(
        cloudURLService: CloudURLServicing = CloudURLService(),
        opener: Opening = Opener()
    ) {
        self.cloudURLService = cloudURLService
        self.opener = opener
    }

    func run(
        organizationName: String,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)
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
