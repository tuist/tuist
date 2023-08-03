import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudProjectCreateServicing {
    func run(
        name: String,
        organization: String?,
        serverURL: String?
    ) async throws
}

final class CloudProjectCreateService: CloudProjectCreateServicing {
    private let createProjectService: CreateProjectNextServicing
    private let cloudURLService: CloudURLServicing

    init(
        createProjectService: CreateProjectNextServicing = CreateProjectNextService(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.createProjectService = createProjectService
        self.cloudURLService = cloudURLService
    }

    func run(
        name: String,
        organization: String?,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        let project = try await createProjectService.createProject(
            name: name,
            organization: organization,
            serverURL: cloudURL
        )

        logger.info("Cloud project \(project.fullName) was successfully created 🎉")
    }
}
