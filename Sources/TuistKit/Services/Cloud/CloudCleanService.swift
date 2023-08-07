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
    case cloudNotFound

    /// Error description.
    var description: String {
        switch self {
        case .cloudNotFound:
            return "You are missing Cloud configuration in your Config.swift. Run `tuist cloud init` to set up Cloud."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cloudNotFound:
            return .abort
        }
    }
}

final class CloudCleanService: CloudCleanServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cleanCacheService: CleanCacheServicing
    private let configLoader: ConfigLoading

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cleanCacheService: CleanCacheServicing = CleanCacheService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cleanCacheService = cleanCacheService
        self.configLoader = configLoader
    }

    func clean(path: String?) async throws {
        let path: AbsolutePath = try self.path(path)
        let config = try configLoader.loadConfig(path: path)

        guard let cloud = config.cloud else { throw CloudCleanServiceError.cloudNotFound }
        try await cleanCacheService.cleanCache(
            serverURL: cloud.url,
            fullName: cloud.projectId
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
