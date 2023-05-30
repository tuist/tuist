import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudInitServicing {
    func createProject(
        name: String,
        owner: String?,
        url: String,
        path: String?
    ) async throws
}

enum CloudInitServiceError: FatalError, Equatable {
    case invalidCloudURL(String)
    case cloudAlreadySetUp

    /// Error description.
    var description: String {
        switch self {
        case let .invalidCloudURL(url):
            return "The cloud URL \(url) is invalid."
        case .cloudAlreadySetUp:
            return "The project is already set up with Tuist Cloud."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidCloudURL, .cloudAlreadySetUp:
            return .abort
        }
    }
}

final class CloudInitService: CloudInitServicing {
    private let cloudSessionController: CloudSessionControlling
    private let createProjectService: CreateProjectServicing
    private let configLoader: ConfigLoading

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        createProjectService: CreateProjectServicing = CreateProjectService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cloudSessionController = cloudSessionController
        self.createProjectService = createProjectService
        self.configLoader = configLoader
    }

    func createProject(
        name: String,
        owner: String?,
        url: String,
        path: String?
    ) async throws {
        guard let serverURL = URL(string: url)
        else {
            throw CloudInitServiceError.invalidCloudURL(url)
        }

        let path = try self.path(path)
        let config = try configLoader.loadConfig(path: path)

        if config.cloud != nil {
            throw CloudInitServiceError.cloudAlreadySetUp
        }

        let slug = try await createProjectService.createProject(
            name: name,
            organizationName: owner,
            serverURL: serverURL
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
                    cloud: .cloud(projectId: "\(slug)", url: "\(url)")
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
                cloud: .cloud(projectId: "\(slug)", url: "\(url)")
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
