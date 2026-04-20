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

    init(
        fileSystem: FileSysteming = FileSystem(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService()
    ) {
        self.fileSystem = fileSystem
        self.uploadAnalyticsService = uploadAnalyticsService
    }

    func run(eventFilePath: String, fullHandle: String, serverURL: String, sessionDirectory: String? = nil) async throws {
        let eventPath = try AbsolutePath(validating: eventFilePath)
        let sessionDirectory = try sessionDirectory.map { try AbsolutePath(validating: $0) }
        do {
            guard let url = URL(string: serverURL) else {
                throw AnalyticsUploadCommandServiceError.invalidServerURL(serverURL)
            }

            let commandEvent: CommandEvent = try await fileSystem.readJSONFile(at: eventPath)

            _ = try await uploadAnalyticsService.upload(
                commandEvent: commandEvent,
                fullHandle: fullHandle,
                serverURL: url,
                sessionDirectory: sessionDirectory
            )
        } catch {
            try? await fileSystem.remove(eventPath)
            throw error
        }

        try? await fileSystem.remove(eventPath)
    }
}
