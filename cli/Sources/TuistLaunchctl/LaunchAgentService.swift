import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
import TuistLogging

public enum LaunchAgentServiceError: Equatable, LocalizedError {
    case failedToLoadLaunchAgent(String)
    case failedToBootOutLaunchAgent(String)
    case missingExecutablePath

    public var errorDescription: String? {
        switch self {
        case let .failedToLoadLaunchAgent(error):
            return "Failed to load LaunchAgent: \(error)"
        case let .failedToBootOutLaunchAgent(error):
            return "Failed to boot out the LaunchAgent that is already running: \(error)"
        case .missingExecutablePath:
            return "Failed to determine the current tuist executable path"
        }
    }
}

@Mockable
public protocol LaunchAgentServicing {
    /// Bootstraps the agent, returning the process it displaced when a job was
    /// already running under the label.
    ///
    /// A caller that goes on to check the agent's readiness needs it: whatever
    /// answers on the agent's endpoint straight afterwards can still be the
    /// displaced process, serving out its last moments from the configuration
    /// this call replaced.
    @discardableResult
    func setupLaunchAgent(
        label: String,
        plistFileName: String,
        programArguments: [String],
        environmentVariables: [String: String]
    ) async throws -> Int32?

    func teardownLaunchAgent(
        label: String,
        plistFileName: String
    ) async throws

    func restartLaunchAgent(label: String) async throws

    /// The process currently running the agent, or `nil` when the label is not in
    /// the domain, when launchd holds it without a process, or when launchd
    /// cannot be asked.
    func runningProcessIdentifier(label: String) async -> Int32?

    /// Whether a process is running exactly what `setupLaunchAgent` would install
    /// for the same arguments, so that installing it again would replace the
    /// process and change nothing else.
    ///
    /// `launchInputs` are files the agent reads once, when it starts. A process
    /// that started before one of them last changed is still running the old
    /// one, however identical its plist.
    func isLaunchAgentCurrent(
        label: String,
        plistFileName: String,
        programArguments: [String],
        environmentVariables: [String: String],
        launchInputs: [AbsolutePath]
    ) async -> Bool
}

public struct LaunchAgentService: LaunchAgentServicing {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling
    private let bootoutTimeout: Duration
    private let processLaunchDate: @Sendable (Int32) -> Date?

    public init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController(),
        bootoutTimeout: Duration = .seconds(3),
        processLaunchDate: @escaping @Sendable (Int32) -> Date? = { LaunchAgentService.launchDate(ofProcess: $0) }
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
        self.bootoutTimeout = bootoutTimeout
        self.processLaunchDate = processLaunchDate
    }

    @discardableResult
    public func setupLaunchAgent(
        label: String,
        plistFileName: String,
        programArguments: [String],
        environmentVariables: [String: String] = [:]
    ) async throws -> Int32? {
        let tuistBinaryPath = try await determineTuistBinaryPath()
        let domain = try await launchctlController.preferredDomain()

        let launchAgentsDir = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents"
        )
        let plistPath = launchAgentsDir.appending(component: plistFileName)

        if try await !fileSystem.exists(launchAgentsDir) {
            try await fileSystem.makeDirectory(at: launchAgentsDir)
        }

        let outgoingJob = try await launchctlController.job(label: label)
        if outgoingJob != nil {
            Logger.current.debug("Existing LaunchAgent found. Booting out...")
            do {
                try await launchctlController.bootout(label: label)
            } catch {
                // A job on its way out is exactly what makes launchctl refuse a
                // bootout, so this failure reaches the user on an ordinary setup.
                // Typed rather than the raw launchctl termination, which surfaces
                // as an unreadable `CommandError` dump.
                throw LaunchAgentServiceError.failedToBootOutLaunchAgent(String(describing: error))
            }
            await waitUntilBootedOut(label: label)
        }

        if try await fileSystem.exists(plistPath) {
            try await fileSystem.remove(plistPath)
        }

        let logDirectory = Environment.current.stateDirectory
        if try await !fileSystem.exists(logDirectory) {
            try await fileSystem.makeDirectory(at: logDirectory)
        }
        let stderrLogPath = logDirectory.appending(component: "\(label).stderr.log")

        let plistContent = launchAgentPlist(
            label: label,
            tuistBinaryPath: tuistBinaryPath,
            programArguments: programArguments,
            environmentVariables: environmentVariables,
            domain: domain
        )

        try await fileSystem.writeText(plistContent, at: plistPath)

        Logger.current.debug("Created LaunchAgent plist at: \(plistPath.pathString)")

        do {
            try await launchctlController.bootstrap(plistPath: plistPath, domain: domain)
            Logger.current.debug("Bootstrapped LaunchAgent")
        } catch let commandError as CommandError {
            // `5` is launchd's catch-all, covering both a label that is already
            // bootstrapped and a plist it cannot load at all, so the code alone
            // cannot decide. Ask the domain instead — and ask which PROCESS holds
            // the label, not merely whether the label is there.
            //
            // The label alone answers "yes" for the job booted out above that has
            // not finished leaving, which is the case where the plist just written
            // is precisely what is NOT bootstrapped. Reading that as success hands
            // the caller a proxy that exits moments later, and a readiness check
            // against its socket confirms it. Only a process launchd spawned after
            // the bootout means this configuration is live.
            //
            // Deliberately narrower than the blanket tolerance this replaces
            // (removed in #12014), which reported success for an agent that had
            // genuinely failed to load. Do not widen it back to every `5`.
            if case .terminated(5, _, _) = commandError,
               let liveProcessIdentifier = await jobIgnoringFailures(label: label)?.processIdentifier,
               liveProcessIdentifier != outgoingJob?.processIdentifier
            {
                Logger.current.debug(
                    "launchctl refused to bootstrap \(label), which is already loaded under \(liveProcessIdentifier): \(commandError)"
                )
                return outgoingJob?.processIdentifier
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

        return outgoingJob?.processIdentifier
    }

    public func runningProcessIdentifier(label: String) async -> Int32? {
        await jobIgnoringFailures(label: label).flatMap(\.processIdentifier)
    }

    public func isLaunchAgentCurrent(
        label: String,
        plistFileName: String,
        programArguments: [String],
        environmentVariables: [String: String],
        launchInputs: [AbsolutePath]
    ) async -> Bool {
        guard let tuistBinaryPath = try? await determineTuistBinaryPath(),
              let domain = try? await launchctlController.preferredDomain(),
              let processIdentifier = await runningProcessIdentifier(label: label),
              let launchedAt = processLaunchDate(processIdentifier)
        else { return false }

        let plistPath = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents", plistFileName
        )
        // Compared as property lists rather than as text: the environment is
        // rendered from a dictionary, whose order changes from one process to
        // the next.
        guard let installed = try? await fileSystem.readTextFile(at: plistPath),
              let installedPropertyList = propertyList(installed),
              let expectedPropertyList = propertyList(launchAgentPlist(
                  label: label,
                  tuistBinaryPath: tuistBinaryPath,
                  programArguments: programArguments,
                  environmentVariables: environmentVariables,
                  domain: domain
              )),
              installedPropertyList.isEqual(expectedPropertyList)
        else { return false }

        // launchd reads the plist when the agent is bootstrapped, and the process
        // reads its binary and inputs when it starts, so a process older than any
        // of them is running what they replaced. A file that cannot be inspected
        // is not evidence that it did not change.
        return ([plistPath, tuistBinaryPath] + launchInputs).allSatisfy { path in
            statusChangeDate(of: path).map { $0 < launchedAt } ?? false
        }
    }

    /// When the process started, or `nil` when it cannot be inspected. The start
    /// survives `execv`, so for an agent it is when launchd spawned the job.
    public static func launchDate(ofProcess processIdentifier: Int32) -> Date? {
        #if os(macOS)
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Date(
                timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
            )
        #else
            return nil
        #endif
    }

    /// `bootout` returns once launchd has accepted the removal, not once the job
    /// has left the domain, so a bootstrap issued straight after can still land
    /// on the outgoing label. Waiting also stops a caller's readiness check from
    /// passing against the previous daemon, which would report success for a
    /// configuration that never took effect.
    ///
    /// Gives up rather than throwing: a label that outlives the wait is not itself
    /// a failure, and the bootstrap after it settles the question anyway by
    /// requiring a process other than the one being booted out.
    private func waitUntilBootedOut(label: String) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: bootoutTimeout)

        while clock.now < deadline, !Task.isCancelled {
            if await jobIgnoringFailures(label: label) == nil { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        Logger.current.debug("\(label) is still loaded after booting it out. Continuing.")
    }

    private func jobIgnoringFailures(label: String) async -> LaunchAgentJob? {
        guard let job = try? await launchctlController.job(label: label) else { return nil }
        return job
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

        if try await launchctlController.job(label: label) != nil {
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
        label: String,
        tuistBinaryPath: AbsolutePath,
        programArguments: [String],
        environmentVariables: [String: String],
        domain: LaunchAgentDomain
    ) -> String {
        let logDirectory = Environment.current.stateDirectory
        return launchAgentPlist(
            programPath: tuistBinaryPath.pathString,
            programArguments: [tuistBinaryPath.pathString] + programArguments,
            label: label,
            domain: domain,
            environmentVariables: environmentVariables,
            standardOutPath: logDirectory.appending(component: "\(label).stdout.log").pathString,
            standardErrorPath: logDirectory.appending(component: "\(label).stderr.log").pathString
        )
    }

    private func launchAgentPlist(
        programPath: String,
        programArguments: [String],
        label: String,
        domain: LaunchAgentDomain,
        environmentVariables: [String: String] = [:],
        standardOutPath: String,
        standardErrorPath: String
    ) -> String {
        let programArgumentsXML = programArguments.map { "<string>\($0)</string>" }.joined(separator: "\n\t\t")

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
            <key>LimitLoadToSessionType</key>
            <string>\(domain.sessionType)</string>
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

/// The file's `st_ctime`, following symlinks. Unlike the modification date,
/// an installer cannot carry it over from an archive, so a binary replaced by
/// an older-dated copy still reads as changed.
private func statusChangeDate(of path: AbsolutePath) -> Date? {
    var status = stat()
    guard stat(path.pathString, &status) == 0 else { return nil }
    #if os(Linux)
        let changedAt = status.st_ctim
    #else
        let changedAt = status.st_ctimespec
    #endif
    return Date(timeIntervalSince1970: TimeInterval(changedAt.tv_sec) + TimeInterval(changedAt.tv_nsec) / 1_000_000_000)
}

private func propertyList(_ contents: String) -> NSDictionary? {
    try? PropertyListSerialization.propertyList(from: Data(contents.utf8), format: nil) as? NSDictionary
}
