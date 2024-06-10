import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CloudProjectListServicing {
    func run(
        json: Bool,
        directory: String?
    ) async throws
}

final class CloudProjectListService: CloudProjectListServicing {
    private let listProjectsService: ListProjectsServicing
    private let cloudURLService: CloudURLServicing
    private let configLoader: ConfigLoading

    init(
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        cloudURLService: CloudURLServicing = CloudURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listProjectsService = listProjectsService
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
