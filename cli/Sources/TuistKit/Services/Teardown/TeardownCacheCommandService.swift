import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLaunchctl
import TuistLoader
import TuistLogging

enum TeardownCacheCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        }
    }
}

struct TeardownCacheCommandService {
    private let launchAgentService: LaunchAgentServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.launchAgentService = launchAgentService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
    }

    func run(
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else {
            throw TeardownCacheCommandServiceError.missingFullHandle
        }

        let label = Environment.current.cacheLaunchAgentLabel(for: fullHandle)

        try await launchAgentService.teardownLaunchAgent(
            label: label,
            plistFileName: "\(label).plist"
        )

        let socketPath = Environment.current.cacheSocketPath(for: fullHandle)
        if try await fileSystem.exists(socketPath) {
            try await fileSystem.remove(socketPath)
        }

        Logger.current.info("Xcode Cache has been torn down 🧹", metadata: .success)
    }
}
