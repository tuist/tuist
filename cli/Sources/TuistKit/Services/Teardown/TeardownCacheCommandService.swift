import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLaunchctl
import TuistLoader
import TuistLogging

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
        } else {
            // Without a resolvable fullHandle we can't name the per-project legacy
            // daemon agent, so one (if installed) is left running. Surface that
            // rather than let the success message imply a clean teardown.
            Logger.current
                .warning(
                    "Could not resolve a project fullHandle, so a legacy per-project Xcode cache daemon (if one was installed) could not be identified and may still be running. Run `tuist teardown cache` from the project directory to remove it."
                )
        }

        Logger.current.info("Xcode Cache has been torn down 🧹", metadata: .success)
    }
}
