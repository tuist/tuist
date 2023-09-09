import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudInitServicing {
    func createProject(
        name: String,
        organization: String?,
        serverURL: String?,
        path: String?
    ) async throws
}

enum CloudInitServiceError: FatalError, Equatable {
    case cloudAlreadySetUp

    /// Error description.
    var description: String {
        switch self {
        case .cloudAlreadySetUp:
            return "The project is already set up with Tuist Cloud."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cloudAlreadySetUp:
            return .abort
        }
    }
}

final class CloudInitService: CloudInitServicing {
    private let cloudSessionController: CloudSessionControlling
    private let createProjectService: CreateProjectServicing
    private let configLoader: ConfigLoading
    private let cloudURLService: CloudURLServicing

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        createProjectService: CreateProjectServicing = CreateProjectService(),
        configLoader: ConfigLoading = ConfigLoader(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.cloudSessionController = cloudSessionController
        self.createProjectService = createProjectService
        self.configLoader = configLoader
        self.cloudURLService = cloudURLService
    }

    func createProject(
        name: String,
        organization: String?,
        serverURL: String?,
        path: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        let path = try self.path(path)
        let config = try configLoader.loadConfig(path: path)

        if config.cloud != nil {
            throw CloudInitServiceError.cloudAlreadySetUp
        }

        let project = try await createProjectService.createProject(
            name: name,
            organization: organization,
            serverURL: cloudURL
        )

        if configLoader.locateConfig(at: path) == nil {
            let tuistDirectoryPath = path.appending(component: Constants.tuistDirectoryName)
            if !FileHandler.shared.exists(tuistDirectoryPath) {
                try FileHandler.shared.createFolder(tuistDirectoryPath)
            }
            try FileHandler.shared.write(
                """
                import ProjectDescription

                let config = Config(
                    cloud: .cloud(projectId: "\(project.fullName)", url: "\(cloudURL)")
                )

                """,
                path: tuistDirectoryPath.appending(component: Manifest.config.fileName(path)),
                atomically: true
            )
            logger.info(
                """
                Tuist Cloud was successfully initialized.
                """
            )
        } else {
            logger.info(
                """
                Put the following line into your Tuist/Config.swift (see the docs for more: https://docs.tuist.io/manifests/config/):
                cloud: .cloud(projectId: "\(project.fullName)", url: "\(cloudURL)")
                """
            )
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
