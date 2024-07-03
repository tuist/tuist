import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectListServicing {
    func run(
        json: Bool,
        directory: String?
    ) async throws
}

final class ProjectListService: ProjectListServicing {
    private let listProjectsService: ListProjectsServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listProjectsService = listProjectsService
        self.serverURLService = serverURLService
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
        let cloudURL = try serverURLService.url(configServerURL: config.cloud?.url)

        let projects = try await listProjectsService.listProjects(
            serverURL: cloudURL
        )

        if json {
            let json = try projects.toJSON()
            logger.info(.init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json)
            return
        }

        if projects.isEmpty {
            logger.info("You currently have no Tuist projects. Create one by running `tuist project create`.")
            return
        }

        let projectsString = "Listing all your projects:\n" + projects.map { "  • \($0.fullName)" }.joined(separator: "\n")
        logger.info("\(projectsString)")
    }
}
