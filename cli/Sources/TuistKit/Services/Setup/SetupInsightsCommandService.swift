import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLaunchctl
import TuistLogging
import TuistSupport

enum SetupInsightsCommandServiceError: Equatable, LocalizedError {
    case failedToLoadLaunchDaemon(String)
    case missingExecutablePath

    var errorDescription: String? {
        switch self {
        case let .failedToLoadLaunchDaemon(error):
            return "Failed to load LaunchDaemon: \(error)"
        case .missingExecutablePath:
            return "Failed to determine the current tuist executable path"
        }
    }
}

struct SetupInsightsCommandService {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling

    init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController()
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
    }

    func run(
        path _: String? = nil
    ) async throws {
        let tuistBinaryPath = try await determineTuistBinaryPath()
        let launchDaemonPlistPath = try await createLaunchDaemonPlist(
            tuistBinaryPath: tuistBinaryPath
        )

        try await launchDaemon(plistPath: launchDaemonPlistPath)

        Logger.current.debug("LaunchAgent configured and loaded successfully")
        Logger.current.info("Machine metrics daemon has been set up successfully")
    }

    private func createLaunchDaemonPlist(
        tuistBinaryPath: AbsolutePath
    ) async throws -> AbsolutePath {
        let launchAgentsDir = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents"
        )
        let plistFileName = "tuist.insights.plist"
        let plistPath = launchAgentsDir.appending(component: plistFileName)

        if try await !fileSystem.exists(launchAgentsDir) {
            try await fileSystem.makeDirectory(at: launchAgentsDir)
        }

        if try await fileSystem.exists(plistPath) {
            Logger.current.debug("Existing LaunchAgent found. Unloading...")
            do {
                try await launchctlController.unload(plistPath: plistPath)
            } catch {
                Logger.current.debug(
                    "Failed to unload existing LaunchAgent: \(error.localizedDescription)"
                )
            }
            try await fileSystem.remove(plistPath)
        }

        let programArguments = [
            tuistBinaryPath.pathString,
            "insights-start",
        ]

        let plistContent = launchAgentPlist(
            programPath: tuistBinaryPath.pathString,
            programArguments: programArguments,
            label: "tuist.insights"
        )

        try await fileSystem.writeText(plistContent, at: plistPath)

        Logger.current.debug("Created LaunchDaemon plist at: \(plistPath.pathString)")

        return plistPath
    }

    private func launchAgentPlist(
        programPath: String,
        programArguments: [String],
        label: String
    ) -> String {
        let programArgumentsXML =
            programArguments
                .map { "<string>\($0)</string>" }
                .joined(separator: "\n\t\t")

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

    private func launchDaemon(plistPath: AbsolutePath) async throws {
        do {
            try await launchctlController.load(plistPath: plistPath)
            Logger.current.debug("Loaded LaunchAgent")
        } catch {
            throw SetupInsightsCommandServiceError.failedToLoadLaunchDaemon(error.localizedDescription)
        }
    }

    private func determineTuistBinaryPath() async throws -> AbsolutePath {
        guard let currentPath = Environment.current.currentExecutablePath() else {
            throw SetupInsightsCommandServiceError.missingExecutablePath
        }

        if currentPath.pathString.contains("/.local/share/mise/installs/tuist/") {
            let homeDir = Environment.current.homeDirectory

            let misePath = homeDir.appending(
                components: ".local", "share", "mise", "installs", "tuist", "latest", "tuist"
            )
            if try await fileSystem.exists(misePath) {
                return misePath
            }

            let oldMisePath = homeDir.appending(
                components: ".local", "share", "mise", "installs", "tuist", "latest", "bin", "tuist"
            )
            if try await fileSystem.exists(oldMisePath) {
                return oldMisePath
            }
        }

        return currentPath
    }
}
