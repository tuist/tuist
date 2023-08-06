import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudProjectTokenServicing {
    func run(
        projectName: String,
        organizationName: String?,
        serverURL: String?
    ) async throws
}

final class CloudProjectTokenService: CloudProjectTokenServicing {
    private let getProjectService: GetProjectServicing
    private let credentialsStore: CredentialsStoring
    private let cloudURLService: CloudURLServicing

    init(
        getProjectService: GetProjectServicing = GetProjectService(),
        credentialsStore: CredentialsStoring = CredentialsStore(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.getProjectService = getProjectService
        self.credentialsStore = credentialsStore
        self.cloudURLService = cloudURLService
    }

    func run(
        projectName: String,
        organizationName: String?,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        let accountName: String
        if let organizationName = organizationName {
            accountName = organizationName
        } else {
            let credentials = try credentialsStore.get(serverURL: cloudURL)
            accountName = credentials.account
        }

        let project = try await getProjectService.getProject(
            accountName: accountName,
            projectName: projectName,
            serverURL: cloudURL
        )

        logger.info(.init(stringLiteral: project.token))
    }
}
