import Foundation
import TSCBasic
import TuistLoader
import TuistServer
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
    private let cloudURLService: CloudURLServicing

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cleanCacheService: CleanCacheServicing = CleanCacheService(),
        configLoader: ConfigLoading = ConfigLoader(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cleanCacheService = cleanCacheService
        self.configLoader = configLoader
        self.cloudURLService = cloudURLService
    }

    func clean(path: String?) async throws {
        let path: AbsolutePath = try self.path(path)
        let config = try configLoader.loadConfig(path: path)

        guard let cloud = config.cloud else { throw CloudCleanServiceError.cloudNotFound }
        let cloudURL = try cloudURLService.url(configCloudURL: cloud.url)
        try await cleanCacheService.cleanCache(
            serverURL: cloudURL,
            fullName: cloud.projectId
        )

        logger.info("Project was successfully cleaned.")
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
