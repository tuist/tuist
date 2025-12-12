import FileSystem
import Foundation
import Path
import TuistCore
import TuistServer
import TuistSupport

enum AnalyticsUploadCommandServiceError: LocalizedError, Equatable {
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}

struct AnalyticsUploadCommandService {
    private let fileSystem: FileSysteming
    private let uploadAnalyticsService: UploadAnalyticsServicing
    private let retryProvider: RetryProviding

    init(
        fileSystem: FileSysteming = FileSystem(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService(),
        retryProvider: RetryProviding = RetryProvider()
    ) {
        self.fileSystem = fileSystem
        self.uploadAnalyticsService = uploadAnalyticsService
        self.retryProvider = retryProvider
    }

    func run(eventFilePath: String, fullHandle: String, serverURL: String) async throws {
        let eventPath = try AbsolutePath(validating: eventFilePath)

        defer {
            Task {
                try await fileSystem.remove(eventPath)
            }
        }

        guard let url = URL(string: serverURL) else {
            throw AnalyticsUploadCommandServiceError.invalidServerURL(serverURL)
        }

        let commandEvent: CommandEvent = try await fileSystem.readJSONFile(at: eventPath)

        _ = try await retryProvider.runWithRetries {
            try await uploadAnalyticsService.upload(
                commandEvent: commandEvent,
                fullHandle: fullHandle,
                serverURL: url
            )
        }
    }
}
