import FileSystem
import Foundation
import Path
import TuistCore
import TuistConfigLoader
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
    private let configLoader: ConfigLoading

    init(
        fileSystem: FileSysteming = FileSystem(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.fileSystem = fileSystem
        self.uploadAnalyticsService = uploadAnalyticsService
        self.configLoader = configLoader
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
                _ = try await uploadAnalyticsService.upload(
                    commandEvent: commandEvent,
                    fullHandle: fullHandle,
                    serverURL: url,
                    sessionDirectory: sessionDirectory
                )
            }
        }
    }

    private func resolveOptionalAuthentication(commandArguments: [String]) async -> Bool {
        guard let path = try? await CommandArguments.path(in: commandArguments),
              let config = try? await configLoader.loadConfig(path: path)
        else { return false }

        return config.project.generatedProject?.generationOptions.optionalAuthentication == true
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
