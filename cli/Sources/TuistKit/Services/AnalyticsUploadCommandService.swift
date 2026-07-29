import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistCore
import TuistServer
import TuistSupport

enum AnalyticsUploadCommandServiceError: LocalizedError, Equatable {
    case invalidServerURL(String)
    case uploadTimedOut

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        case .uploadTimedOut:
            return "Run metadata upload timed out."
        }
    }
}

struct AnalyticsUploadCommandService {
    private let fileSystem: FileSysteming
    private let uploadAnalyticsService: UploadAnalyticsServicing
    private let configLoader: ConfigLoading
    private let bestEffortUploadTimeout: Duration

    init(
        fileSystem: FileSysteming = FileSystem(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService(),
        configLoader: ConfigLoading = ConfigLoader(),
        bestEffortUploadTimeout: Duration = .seconds(15)
    ) {
        self.fileSystem = fileSystem
        self.uploadAnalyticsService = uploadAnalyticsService
        self.configLoader = configLoader
        self.bestEffortUploadTimeout = bestEffortUploadTimeout
    }

    func run(
        eventFilePath: String,
        fullHandle: String,
        serverURL: String,
        sessionDirectory: String? = nil
    ) async throws {
        let eventPath = try AbsolutePath(validating: eventFilePath)
        let sessionDirectory = try sessionDirectory.map { try AbsolutePath(validating: $0) }
        try await withCleanup(of: eventPath) {
            guard let url = URL(string: serverURL) else {
                throw AnalyticsUploadCommandServiceError.invalidServerURL(serverURL)
            }

            let commandEvent: CommandEvent = try await fileSystem.readJSONFile(at: eventPath)
            let optionalAuthentication = await resolveOptionalAuthentication(commandArguments: commandEvent.commandArguments)
            try await ServerAuthenticationConfig.withOptionalAuthentication(optionalAuthentication) {
                try await withTimeout(
                    bestEffortUploadTimeout,
                    onTimeout: {
                        throw AnalyticsUploadCommandServiceError.uploadTimedOut
                    },
                    action: {
                        _ = try await uploadAnalyticsService.upload(
                            commandEvent: commandEvent,
                            fullHandle: fullHandle,
                            serverURL: url,
                            sessionDirectory: sessionDirectory
                        )
                    }
                )
            }
        }
    }

    private func resolveOptionalAuthentication(commandArguments: [String]) async -> Bool {
        guard let path = try? await CommandArguments.path(in: commandArguments),
              let config = try? await configLoader.loadConfig(path: path)
        else { return false }

        return config.project.optionalAuthentication
    }

    private func withCleanup<T>(
        of path: AbsolutePath,
        _ operation: () async throws -> T
    ) async throws -> T {
        let result: Result<T, Error>

        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }

        try? await fileSystem.remove(path)
        return try result.get()
    }
}
