import Foundation
import Path
import TuistLoader
import TuistSupport

protocol AnalyticsServicing {
    func run(
        path: String?
    ) async throws
}

final class AnalyticsService: AnalyticsServicing {
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

        guard let cloud = config.cloud else { throw RemoteCleanServiceError.cloudNotFound }
        try opener.open(
            url: cloud.url
                .appendingPathComponent(cloud.projectId)
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
