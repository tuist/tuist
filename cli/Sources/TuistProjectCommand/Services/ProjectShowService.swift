import Foundation
import Mockable
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistOpener
import TuistServer

enum ProjectShowServiceError: Equatable, FatalError {
    case missingFullHandle

    var type: ErrorType {
        switch self {
        case .missingFullHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return
                "We couldn't show the project because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct ProjectShowService {
    private let opener: Opening
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let getProjectService: GetProjectServicing

    init(
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        getProjectService: GetProjectServicing = GetProjectService()
    ) {
        self.opener = opener
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.getProjectService = getProjectService
    }

    func run(
        fullHandle: String?,
        web: Bool,
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: path)
        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw ProjectShowServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        if web {
            var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
            components.path = "/\(fullHandle)"
            try opener.open(url: components.url!)
        } else {
            let project = try await getProjectService.getProject(
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            var projectInfo = [
                "Project".bold(),
                "Full handle: \(fullHandle)",
            ]

            if let repositoryURL = project.repositoryURL {
                projectInfo.append("Repository: \(repositoryURL)")
            }

            projectInfo.append("Default branch: \(project.defaultBranch)")
            projectInfo.append("Visibility: \(project.visibility.rawValue)")

            Logger.current.info("\(projectInfo.joined(separator: "\n"))")
        }
    }
}
