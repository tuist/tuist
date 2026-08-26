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

    func restartLaunchAgent(label: String) async throws
}

public struct LaunchAgentService: LaunchAgentServicing {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling
    private let bootoutTimeout: Duration

    public init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController(),
        bootoutTimeout: Duration = .seconds(3)
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
        self.bootoutTimeout = bootoutTimeout
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

        if try await launchctlController.isLoaded(label: label) {
            Logger.current.debug("Existing LaunchAgent found. Booting out...")
            try await launchctlController.bootout(label: label)
            await waitUntilBootedOut(label: label)
        }

        if try await fileSystem.exists(plistPath) {
            try await fileSystem.remove(plistPath)
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
            // `5` is launchd's catch-all, covering both a label that is already
            // bootstrapped and a plist it cannot load at all, so the code alone
            // cannot decide. Ask the domain instead: the label being there means
            // the bootstrap was redundant and setup has what it wanted.
            //
            // Deliberately narrower than the blanket tolerance this replaces
            // (removed in #12014), which reported success for an agent that had
            // genuinely failed to load. Do not widen it back to every `5`.
            if case .terminated(5, _, _) = commandError,
               await isLoadedIgnoringFailures(label: label)
            {
                Logger.current.debug(
                    "launchctl refused to bootstrap \(label), which is already loaded: \(commandError)"
                )
                return
            }
            var message = String(describing: commandError)
            if let stderrContent = try? await fileSystem.readTextFile(at: stderrLogPath),
               !stderrContent.isEmpty
            {
                message += "\nDaemon stderr log:\n\(stderrContent)"
            }
            throw LaunchAgentServiceError.failedToLoadLaunchAgent(message)
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

    /// `bootout` returns once launchd has accepted the removal, not once the job
    /// has left the domain, so a bootstrap issued straight after can still land
    /// on the outgoing label. Waiting also stops a caller's readiness check from
    /// passing against the previous daemon, which would report success for a
    /// configuration that never took effect.
    ///
    /// Gives up rather than throwing: a label that outlives the wait leaves the
    /// bootstrap facing the same ambiguity it already resolves against the
    /// domain.
    private func waitUntilBootedOut(label: String) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: bootoutTimeout)

        while clock.now < deadline, !Task.isCancelled {
            if await !isLoadedIgnoringFailures(label: label) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        Logger.current.debug("\(label) is still loaded after booting it out. Continuing.")
    }

    private func isLoadedIgnoringFailures(label: String) async -> Bool {
        (try? await launchctlController.isLoaded(label: label)) ?? false
    }

    public func restartLaunchAgent(label: String) async throws {
        try await launchctlController.kickstart(label: label)
        Logger.current.debug("Restarted LaunchAgent \(label)")
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
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
        </dict>
        </plist>
        """
    }
}
