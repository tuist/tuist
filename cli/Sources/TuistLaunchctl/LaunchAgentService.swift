import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLogging

public enum LaunchAgentServiceError: Equatable, LocalizedError {
    case failedToLoadLaunchAgent(String)
    case missingExecutablePath

    public var errorDescription: String? {
        switch self {
        case let .failedToLoadLaunchAgent(error):
            return "Failed to load LaunchAgent: \(error)"
        case .missingExecutablePath:
            return "Failed to determine the current tuist executable path"
        }
    }
}

public struct LaunchAgentService {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling

    public init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController()
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
    }

    public func setupLaunchAgent(
        label: String,
        plistFileName: String,
        programArguments: [String],
        environmentVariables: [String: String] = [:]
    ) async throws {
        let tuistBinaryPath = try await determineTuistBinaryPath()

        let launchAgentsDir = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents"
        )
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

        let fullArguments = [tuistBinaryPath.pathString] + programArguments

        let plistContent = launchAgentPlist(
            programPath: tuistBinaryPath.pathString,
            programArguments: fullArguments,
            label: label,
            environmentVariables: environmentVariables
        )

        try await fileSystem.writeText(plistContent, at: plistPath)

        Logger.current.debug("Created LaunchAgent plist at: \(plistPath.pathString)")

        do {
            try await launchctlController.load(plistPath: plistPath)
            Logger.current.debug("Loaded LaunchAgent")
        } catch {
            throw LaunchAgentServiceError.failedToLoadLaunchAgent(error.localizedDescription)
        }

        Logger.current.debug("LaunchAgent configured and loaded successfully")
    }

    private func determineTuistBinaryPath() async throws -> AbsolutePath {
        guard let currentPath = Environment.current.currentExecutablePath() else {
            throw LaunchAgentServiceError.missingExecutablePath
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

    private func launchAgentPlist(
        programPath: String,
        programArguments: [String],
        label: String,
        environmentVariables: [String: String] = [:]
    ) -> String {
        let programArgumentsXML =
            programArguments
                .map { "<string>\($0)</string>" }
                .joined(separator: "\n\t\t")

        let environmentVariablesXML: String
        if environmentVariables.isEmpty {
            environmentVariablesXML = ""
        } else {
            let envVarEntries = environmentVariables.map { key, value in
                """
                \t<key>\(key)</key>
                \t<string>\(value)</string>
                """
            }.joined(separator: "\n\t")
            environmentVariablesXML = """
            <key>EnvironmentVariables</key>
            <dict>
            \(envVarEntries)
            </dict>
            """
        }

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
            \(environmentVariablesXML)
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
