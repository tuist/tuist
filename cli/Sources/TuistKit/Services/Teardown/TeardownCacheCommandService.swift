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
        // The proxy is one machine-wide agent, not per-project, so tearing it
        // down needs no fullHandle.
        let proxyLabel = Environment.current.casProxyLaunchAgentLabel()
        try await launchAgentService.teardownLaunchAgent(
            label: proxyLabel,
            plistFileName: "\(proxyLabel).plist"
        )

        // Best-effort teardown of the per-project cache daemon (the non-kura path,
        // and any leftover from before the machine-wide proxy).
        let resolvedPath = try await Environment.current.pathRelativeToWorkingDirectory(path)
        if let config = try? await configLoader.loadConfig(path: resolvedPath),
           let fullHandle = config.fullHandle
        {
            let legacyLabel = Environment.current.cacheLaunchAgentLabel(for: fullHandle)
            try? await launchAgentService.teardownLaunchAgent(
                label: legacyLabel,
                plistFileName: "\(legacyLabel).plist"
            )
            let legacySocket = Environment.current.cacheSocketPath(for: fullHandle)
            if try await fileSystem.exists(legacySocket) {
                try await fileSystem.remove(legacySocket)
            }
        }

        Logger.current.info("Xcode Cache has been torn down 🧹", metadata: .success)
    }
}
