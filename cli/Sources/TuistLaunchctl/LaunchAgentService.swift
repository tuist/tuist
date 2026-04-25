import Command
import FileSystem
import Foundation
import Mockable
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

@Mockable
public protocol LaunchAgentServicing {
    func setupLaunchAgent(
        label: String,
        plistFileName: String,
        programArguments: [String],
        environmentVariables: [String: String]
    ) async throws

    func teardownLaunchAgent(
        label: String,
        plistFileName: String
    ) async throws
}

public struct LaunchAgentService: LaunchAgentServicing {
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
            Logger.current.debug("Existing LaunchAgent found. Booting out...")
            try await fileSystem.remove(plistPath)
            do {
                try await launchctlController.bootout(label: label)
            } catch {
                Logger.current.debug(
                    "Failed to boot out existing LaunchAgent: \(error.localizedDescription)"
                )
            }
        }

        let fullArguments = [tuistBinaryPath.pathString] + programArguments

        let logDirectory = Environment.current.stateDirectory
        if try await !fileSystem.exists(logDirectory) {
            try await fileSystem.makeDirectory(at: logDirectory)
        }
        let stdoutLogPath = logDirectory.appending(component: "\(label).stdout.log")
        let stderrLogPath = logDirectory.appending(component: "\(label).stderr.log")

        let plistContent = launchAgentPlist(
            programPath: tuistBinaryPath.pathString,
            programArguments: fullArguments,
            label: label,
            environmentVariables: environmentVariables,
            standardOutPath: stdoutLogPath.pathString,
            standardErrorPath: stderrLogPath.pathString
        )

        try await fileSystem.writeText(plistContent, at: plistPath)

        Logger.current.debug("Created LaunchAgent plist at: \(plistPath.pathString)")

        do {
            try await launchctlController.bootstrap(plistPath: plistPath)
            Logger.current.debug("Bootstrapped LaunchAgent")
        } catch let commandError as CommandError {
            switch commandError {
            case .terminated(5, _, _):
                Logger.current
                    .debug("LaunchAgent already bootstrapped by launchd, skipping explicit bootstrap")
            default:
                var message = String(describing: commandError)
                if let stderrContent = try? await fileSystem.readTextFile(at: stderrLogPath),
                   !stderrContent.isEmpty
                {
                    message += "\nDaemon stderr log:\n\(stderrContent)"
                }
                throw LaunchAgentServiceError.failedToLoadLaunchAgent(message)
            }
        } catch {
            var message = String(describing: error)
            if let stderrContent = try? await fileSystem.readTextFile(at: stderrLogPath),
               !stderrContent.isEmpty
            {
                message += "\nDaemon stderr log:\n\(stderrContent)"
            }
            throw LaunchAgentServiceError.failedToLoadLaunchAgent(message)
        }

        Logger.current.debug("LaunchAgent configured and loaded successfully")
    }

    public func teardownLaunchAgent(
        label: String,
        plistFileName: String
    ) async throws {
        let plistPath = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents", plistFileName
        )

        if try await launchctlController.isLoaded(label: label) {
            try await launchctlController.bootout(label: label)
            Logger.current.debug("Booted out LaunchAgent")
        }

        if try await fileSystem.exists(plistPath) {
            try await fileSystem.remove(plistPath)
            Logger.current.debug("Removed LaunchAgent plist at: \(plistPath.pathString)")
        }
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
        environmentVariables: [String: String] = [:],
        standardOutPath: String,
        standardErrorPath: String
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
            <key>StandardOutPath</key>
            <string>\(standardOutPath)</string>
            <key>StandardErrorPath</key>
            <string>\(standardErrorPath)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
