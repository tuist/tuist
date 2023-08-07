import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudProjectListServicing {
    func run(
        json: Bool,
        serverURL: String?
    ) async throws
}

final class CloudProjectListService: CloudProjectListServicing {
    private let listProjectsService: ListProjectsServicing
    private let cloudURLService: CloudURLServicing

    init(
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.listProjectsService = listProjectsService
        self.cloudURLService = cloudURLService
    }

    func run(
        json: Bool,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        let projects = try await listProjectsService.listProjects(
            serverURL: cloudURL
        )

        if json {
            let json = try projects.toJSON()
            logger.info(.init(stringLiteral: json.toString(prettyPrint: true)))
            return
        }

        if projects.isEmpty {
            logger.info("You currently have no Cloud projects. Create one by running `tuist cloud project create`.")
            return
        }

        let projectsString = "Listing all your projects:\n" + projects.map { "  • \($0.fullName)" }.joined(separator: "\n")
        logger.info("\(projectsString)")
    }
}
