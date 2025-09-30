import Foundation
import Mockable
import Path
import TuistLoader
import TuistServer
import TuistSupport

enum ProjectUpdateServiceError: Equatable, FatalError {
    case missingFullHandle

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return
                "We couldn't update the project because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct ProjectUpdateService {
    private let opener: Opening
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let updateProjectService: UpdateProjectServicing

    init(
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        updateProjectService: UpdateProjectServicing = UpdateProjectService()
    ) {
        self.opener = opener
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.updateProjectService = updateProjectService
    }

    func run(
        fullHandle: String?,
        defaultBranch: String?,
        visibility: ServerProject.Visibility?,
        path: String?
    ) async throws {
        let path = try self.path(path)

        let config = try await configLoader.loadConfig(path: path)
        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw ProjectUpdateServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        _ = try await updateProjectService.updateProject(
            fullHandle: fullHandle,
            serverURL: serverURL,
            defaultBranch: defaultBranch,
            visibility: visibility
        )

        AlertController.current.success(
            .alert("The project \(fullHandle) was successfully updated 🎉")
        )
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
