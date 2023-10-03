import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudAnalyticsServicing {
    func run(
        path: String?
    ) async throws
}

final class CloudAnalyticsService: CloudAnalyticsServicing {
    private let configLoader: ConfigLoading
    private let opener: Opening

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        opener: Opening = Opener()
    ) {
        self.configLoader = configLoader
        self.opener = opener
    }

    func run(
        path: String?
    ) async throws {
        let path: AbsolutePath = try self.path(path)
        let config = try configLoader.loadConfig(path: path)

        guard let cloud = config.cloud else { throw CloudCleanServiceError.cloudNotFound }
        try opener.open(
            url: cloud.url
                .appendingPathComponent(cloud.projectId)
                .appendingPathComponent("analytics")
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
