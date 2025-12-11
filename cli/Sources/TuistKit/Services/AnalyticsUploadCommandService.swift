import FileSystem
import Foundation
import Path
import TuistCore
import TuistServer
import TuistSupport

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
            try? FileManager.default.removeItem(atPath: eventPath.pathString)
        }

        guard let url = URL(string: serverURL) else {
            return
        }

        let eventData = try await fileSystem.readFile(at: eventPath)
        let commandEvent = try JSONDecoder().decode(CommandEvent.self, from: eventData)

        try await retryProvider.runWithRetries {
            try await uploadAnalyticsService.upload(
                commandEvent: commandEvent,
                fullHandle: fullHandle,
                serverURL: url
            )
        }
    }
}
