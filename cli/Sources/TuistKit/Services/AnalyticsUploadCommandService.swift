import FileSystem
import Foundation
import Path
import TuistCore
import TuistConfigLoader
import TuistEnvironment
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
        do {
            guard let url = URL(string: serverURL) else {
                throw AnalyticsUploadCommandServiceError.invalidServerURL(serverURL)
            }

            let commandEvent: CommandEvent = try await fileSystem.readJSONFile(at: eventPath)
            let optionalAuthentication = await resolveOptionalAuthentication(commandArguments: commandEvent.commandArguments)
            try await withServerAuthenticationConfig(optionalAuthentication: optionalAuthentication) {
                _ = try await uploadAnalyticsService.upload(
                    commandEvent: commandEvent,
                    fullHandle: fullHandle,
                    serverURL: url,
                    sessionDirectory: sessionDirectory
                )
            }
        } catch {
            try? await fileSystem.remove(eventPath)
            throw error
        }

        try? await fileSystem.remove(eventPath)
    }

    private func withServerAuthenticationConfig<T>(
        optionalAuthentication: Bool,
        _ action: () async throws -> T
    ) async throws -> T {
        guard optionalAuthentication else {
            return try await action()
        }
        let currentConfiguration = ServerAuthenticationConfig.current
        return try await ServerAuthenticationConfig.$current.withValue(
            .init(
                backgroundRefresh: currentConfiguration.backgroundRefresh,
                optionalAuthentication: true
            )
        ) {
            try await action()
        }
    }

    private func resolveOptionalAuthentication(commandArguments: [String]) async -> Bool {
        let pathIndex = commandArguments.firstIndex(of: "--path")
        let pathArgument: String? = if let pathIndex, commandArguments.endIndex > pathIndex + 1 {
            commandArguments[pathIndex + 1]
        } else {
            nil
        }
        do {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(pathArgument)
            let config = try await configLoader.loadConfig(path: path)
            return config.project.generatedProject?.generationOptions.optionalAuthentication == true
        } catch {
            return false
        }
    }
}
