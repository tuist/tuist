import FileSystem
import Foundation
import Path
import TuistCore
import TuistLaunchctl
import TuistLoader
import TuistServer
import TuistSupport

enum SetupCacheCommandServiceError: Equatable, LocalizedError {
    case failedToCreateLaunchDaemon(String)
    case failedToLoadLaunchDaemon(String)
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .failedToCreateLaunchDaemon(let error):
            return "Failed to create LaunchDaemon: \(error)"
        case .failedToLoadLaunchDaemon(let error):
            return "Failed to load LaunchDaemon: \(error)"
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        }
    }
}

struct SetupCacheCommandService {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
    }

    func run(
        path: String?
    ) async throws {
        // Load the config to get fullHandle and URL
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else {
            throw SetupCacheCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let currentBinaryPath = Environment.current.currentExecutablePath()!
        let tuistBinaryPath = determineTuistBinaryPath(currentPath: currentBinaryPath)
        let launchDaemonPlistPath = try await createLaunchDaemonPlist(
            fullHandle: fullHandle,
            url: serverURL.absoluteString,
            tuistBinaryPath: tuistBinaryPath
        )

        try await loadLaunchDaemon(plistPath: launchDaemonPlistPath)

        // Start the daemon immediately
        try await startCacheServer(
            fullHandle: fullHandle,
            url: serverURL.absoluteString,
            tuistBinaryPath: tuistBinaryPath
        )
    }

    private func createLaunchDaemonPlist(
        fullHandle: String,
        url: String?,
        tuistBinaryPath: AbsolutePath
    ) async throws -> AbsolutePath {
        let launchAgentsDir = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents")
        let plistFileName =
            "tuist.cache.\(fullHandle.replacingOccurrences(of: "/", with: "_")).plist"
        let plistPath = launchAgentsDir.appending(component: plistFileName)

        if try await !fileSystem.exists(launchAgentsDir) {
            try await fileSystem.makeDirectory(at: launchAgentsDir)
        }

        // If plist already exists, unload it first
        if try await fileSystem.exists(plistPath) {
            Logger.current.info("Existing LaunchAgent found. Unloading...")
            do {
                try await launchctlController.unload(plistPath: plistPath)
            } catch {
                // It's ok if unload fails - the agent might not be loaded
                Logger.current.debug(
                    "Failed to unload existing LaunchAgent: \(error.localizedDescription)")
            }
            try await fileSystem.remove(plistPath)
        }

        var programArguments = [
            tuistBinaryPath.pathString,
            "cache-start",
            fullHandle,
        ]

        if let url = url {
            programArguments.append(contentsOf: ["--url", url])
        }

        let plistContent = createPlistContent(
            programPath: tuistBinaryPath.pathString,
            programArguments: programArguments,
            label: "tuist.cache.\(fullHandle.replacingOccurrences(of: "/", with: "_"))"
        )

        try await fileSystem.writeText(plistContent, at: plistPath)

        Logger.current.info("Created LaunchDaemon plist at: \(plistPath.pathString)")

        return plistPath
    }

    private func createPlistContent(
        programPath: String,
        programArguments: [String],
        label: String
    ) -> String {
        let programArgumentsXML = programArguments.map { "<string>\($0)</string>" }.joined(
            separator: "\n        ")
        let homeDir = Environment.current.homeDirectory.pathString

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(label)</string>
                <key>Program</key>
                <string>\(programPath)</string>
                <key>ProgramArguments</key>
                <array>
                    \(programArgumentsXML)
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
            </dict>
            </plist>
            """
    }

    private func loadLaunchDaemon(plistPath: AbsolutePath) async throws {
        do {
            try await launchctlController.load(plistPath: plistPath)
            Logger.current.info("Loaded LaunchAgent")
        } catch {
            throw SetupCacheCommandServiceError.failedToLoadLaunchDaemon(error.localizedDescription)
        }
    }

    private func startCacheServer(
        fullHandle: String,
        url: String?,
        tuistBinaryPath: AbsolutePath
    ) async throws {
        // Print the socket path that will be created
        let socketPath = Environment.current.stateDirectory
            .appending(component: "\(fullHandle.replacingOccurrences(of: "/", with: "_")).sock")

        // Replace home directory prefix with $HOME for portability
        let homeDir = Environment.current.homeDirectory.pathString
        let socketPathString = socketPath.pathString
        let portableSocketPath: String
        if socketPathString.hasPrefix(homeDir) {
            portableSocketPath = "$HOME" + socketPathString.dropFirst(homeDir.count)
        } else {
            portableSocketPath = socketPathString
        }

        Logger.current.info("LaunchAgent configured and loaded successfully")
        Logger.current.info("Socket path: \(socketPath.pathString)")
        Logger.current.info(
            """
            Set the following build settings in Xcode projects that you want to use caching for:
            COMPILATION_CACHE_ENABLE_CACHING=YES
            COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(portableSocketPath)
            COMPILATION_CACHE_ENABLE_PLUGIN=YES

            Note that `COMPILATION_CACHE_REMOTE_SERVICE_PATH` and `COMPILATION_CACHE_ENABLE_PLUGIN` are currently not directly exposed by Xcode and you need to manually add these as user-defined build settings.
            """)
        Logger.current.info("The cache server will start automatically on boot and is now running")
    }

    private func determineTuistBinaryPath(currentPath: AbsolutePath) -> AbsolutePath {
        // Check if the current executable is mise-managed
        if currentPath.pathString.contains("/.local/share/mise/installs/tuist/") {
            // Use the latest symlink for mise-managed installations
            let homeDir = Environment.current.homeDirectory
            return homeDir.appending(
                components: ".local", "share", "mise", "installs", "tuist", "latest", "bin", "tuist"
            )
        }

        // Fall back to the current executable path
        return currentPath
    }
}
