import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

public protocol CloudCleanServicing {
    func clean(
        path: String?
    ) async throws
}

public enum CloudCleanServiceError: FatalError, Equatable {
    case invalidCloudURL(String)

    /// Error description.
    public var description: String {
        switch self {
        case let .invalidCloudURL(url):
            return "The cloud URL \(url) is invalid."
        }
    }

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .invalidCloudURL:
            return .abort
        }
    }
}

public final class CloudCleanService: CloudCleanServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cleanRemoteCacheStorageService: CleanRemoteCacheStorageServicing
    private let configLoader: ConfigLoading

    public convenience init() {
        self.init(
            cloudSessionController: CloudSessionController(),
            cleanRemoteCacheStorageService: CleanRemoteCacheStorageService(),
            configLoader: ConfigLoader()
        )
    }
    
    init(
        cloudSessionController: CloudSessionControlling,
        cleanRemoteCacheStorageService: CleanRemoteCacheStorageServicing,
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cleanRemoteCacheStorageService = cleanRemoteCacheStorageService
        self.configLoader = configLoader
    }
    
    // MARK: - CloudCleanServicing

    public func clean(path: String?) async throws {
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
