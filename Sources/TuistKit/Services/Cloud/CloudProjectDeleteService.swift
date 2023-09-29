import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudProjectDeleteServicing {
    func run(
        projectName: String,
        organizationName: String?,
        serverURL: String?
    ) async throws
}

final class CloudProjectDeleteService: CloudProjectDeleteServicing {
    private let deleteProjectService: DeleteProjectServicing
    private let getProjectService: GetProjectServicing
    private let credentialsStore: CredentialsStoring
    private let cloudURLService: CloudURLServicing

    init(
        deleteProjectService: DeleteProjectServicing = DeleteProjectService(),
        getProjectService: GetProjectServicing = GetProjectService(),
        credentialsStore: CredentialsStoring = CredentialsStore(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.deleteProjectService = deleteProjectService
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
        if let organizationName {
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

        try await deleteProjectService.deleteProject(
            projectId: project.id,
            serverURL: cloudURL
        )

        logger.info("Successfully deleted the \(project.fullName) project.")
    }
}
