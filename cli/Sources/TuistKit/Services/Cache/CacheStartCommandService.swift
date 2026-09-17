import FileSystem
import Path
import TuistEnvironment
import TuistLaunchctl
import TuistLogging

struct CacheStartCommandService {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling

    init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController()
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
    }

    /// Runs as the LaunchAgent being removed. It deletes the plist and the socket first and boots
    /// the agent out last, because booting out its own job terminates this process. Exiting is not
    /// enough on its own: agents installed with `KeepAlive` set to `true` are restarted on any exit.
    func run(fullHandle: String) async throws {
        let label = Environment.current.cacheLaunchAgentLabel(for: fullHandle)
        let plistPath = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents", "\(label).plist"
        )
        let socketPath = Environment.current.cacheSocketPath(for: fullHandle)

        for path in [plistPath, socketPath] {
            guard try await fileSystem.exists(path) else { continue }
            try await fileSystem.remove(path)
            Logger.current.debug("Removed \(path.pathString)")
        }

        // A failure here would only make launchd restart the stub to try again.
        do {
            try await launchctlController.bootout(label: label)
        } catch {
            Logger.current.debug("Could not boot out \(label): \(error.localizedDescription)")
        }
    }
}
