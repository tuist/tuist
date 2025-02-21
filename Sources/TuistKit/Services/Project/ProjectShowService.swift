import Foundation
import Mockable
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

enum ProjectShowServiceError: Equatable, FatalError {
    case missingFullHandle

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the project because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct ProjectShowService {
    private let opener: Opening
    private let configLoader: ConfigLoading
    private let serverURLService: ServerURLServicing
    private let getProjectService: GetProjectServicing

    init(
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverURLService: ServerURLServicing = ServerURLService(),
        getProjectService: GetProjectServicing = GetProjectService()
    ) {
        self.opener = opener
        self.configLoader = configLoader
        self.serverURLService = serverURLService
        self.getProjectService = getProjectService
    }

    func run(
        fullHandle: String?,
        web: Bool,
        path: String?
    ) async throws {
        let path = try self.path(path)

        let config = try await configLoader.loadConfig(path: path)
        guard let fullHandle = fullHandle ?? config.fullHandle else { throw ProjectShowServiceError.missingFullHandle }

        let serverURL = try serverURLService.url(configServerURL: config.url)

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

            ServiceContext.current?.logger?.info("\(projectInfo.joined(separator: "\n"))")
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
