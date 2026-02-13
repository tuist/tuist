import Foundation
import Path
import TuistConfigLoader
import TuistEncodable
import TuistEnvironment
import TuistLogging
import TuistServer

protocol ProjectListServicing {
    func run(
        json: Bool,
        directory: String?
    ) async throws
}

struct ProjectListService: ProjectListServicing {
    private let listProjectsService: ListProjectsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listProjectsService = listProjectsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        json: Bool,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let projects = try await listProjectsService.listProjects(
            serverURL: serverURL
        )

        if json {
            let json = try projects.toJSON()
            Logger.current.info(.init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json)
            return
        }

        if projects.isEmpty {
            Logger.current
                .info("You currently have no Tuist projects. Create one by running `tuist project create`.")
            return
        }

        let projectsString = "Listing all your projects:\n" + projects.map { "  • \($0.fullName)" }.joined(separator: "\n")
        Logger.current.info("\(projectsString)")
    }
}
