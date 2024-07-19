import Foundation
import Path
import TuistLoader
import TuistSupport

protocol AnalyticsServicing {
    func run(
        path: String?
    ) async throws
}

enum AnalyticsServiceError: FatalError, Equatable {
    case fullHandleNotFound

    /// Error description.
    var description: String {
        switch self {
        case .fullHandleNotFound:
            return "You are missing `fullHandle` in your `Config.swift`."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .fullHandleNotFound:
            return .abort
        }
    }
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
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else { throw AnalyticsServiceError.fullHandleNotFound }
        try opener.open(
            url: config.url
                .appendingPathComponent(fullHandle)
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
