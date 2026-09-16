import FileSystem
import Path
import TuistEnvironment
import TuistLogging

struct CacheStartCommandService {
    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Runs as the LaunchAgent being removed, so it deletes the plist rather than
    /// booting the agent out, which would terminate this process first. Exiting
    /// successfully keeps launchd from starting it again, and without the plist it
    /// is not loaded at the next login.
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
    }
}
