import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudCleanServicing {
    func clean(
        path: String?
    ) async throws
}

enum CloudCleanServiceError: FatalError, Equatable {
    case invalidCloudURL(String)

    /// Error description.
    var description: String {
        switch self {
        case let .invalidCloudURL(url):
            return "The cloud URL \(url) is invalid."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidCloudURL:
            return .abort
        }
    }
}

final class CloudCleanService: CloudCleanServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cleanRemoteCacheStorageService: CleanRemoteCacheStorageServicing
    private let configLoader: ConfigLoading

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cleanRemoteCacheStorageService: CleanRemoteCacheStorageServicing = CleanRemoteCacheStorageService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cleanRemoteCacheStorageService = cleanRemoteCacheStorageService
        self.configLoader = configLoader
    }

    func clean(path: String?) async throws {
        let path: AbsolutePath = try self.path(path)
        let config = try configLoader.loadConfig(path: path)

        guard let cloud = config.cloud else { fatalError() }
        try await cleanRemoteCacheStorageService.cleanRemoteCacheStorage(
            serverURL: cloud.url,
            projectSlug: cloud.projectId
        )

        logger.info("Project was successfully cleaned.")
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
