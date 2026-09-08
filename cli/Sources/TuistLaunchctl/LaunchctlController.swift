import Command
import Foundation
import Mockable
import Path

/// A job in the current user's GUI domain, as `launchctl print` reports it.
public struct LaunchAgentJob: Equatable, Sendable {
    /// The process running the job, absent while launchd holds the label without
    /// one. A job waiting on its respawn throttle prints that way, and so does an
    /// outgoing job whose process has already been reaped but whose record has
    /// not yet left the domain.
    public let processIdentifier: Int32?

    public init(processIdentifier: Int32?) {
        self.processIdentifier = processIdentifier
    }
}

/// Utility to interact with the `launchctl` CLI.
@Mockable
public protocol LaunchctlControlling {
    /// Bootstraps a LaunchAgent from the given plist path into the current user's GUI domain.
    func bootstrap(plistPath: AbsolutePath) async throws

    /// Boots out a LaunchAgent by label from the current user's GUI domain.
    func bootout(label: String) async throws

    /// Restarts a LaunchAgent by label in the current user's GUI domain.
    func kickstart(label: String) async throws

    /// Returns the job the given label names in the current user's GUI domain, or
    /// `nil` when the label is not in the domain.
    ///
    /// The process and not merely the label, because the two answer different
    /// questions: a label is in the domain from the moment it is bootstrapped
    /// until the moment its last job leaves, which spans two different jobs
    /// across a bootout, and only the process tells them apart.
    func job(label: String) async throws -> LaunchAgentJob?
}

public struct LaunchctlController: LaunchctlControlling {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func bootstrap(plistPath: AbsolutePath) async throws {
        let uid = getuid()
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "bootstrap",
                "gui/\(uid)",
                plistPath.pathString,
            ]
        )
        .awaitCompletion()
    }

    public func bootout(label: String) async throws {
        let uid = getuid()
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "bootout",
                "gui/\(uid)/\(label)",
            ]
        )
        .awaitCompletion()
    }

    public func kickstart(label: String) async throws {
        let uid = getuid()
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "kickstart",
                "-k",
                "gui/\(uid)/\(label)",
            ]
        )
        .awaitCompletion()
    }

    public func job(label: String) async throws -> LaunchAgentJob? {
        let uid = getuid()
        do {
            let output = try await commandRunner.run(
                arguments: [
                    "/bin/launchctl",
                    "print",
                    "gui/\(uid)/\(label)",
                ]
            )
            .concatenatedString(including: [.standardOutput])
            return LaunchAgentJob(processIdentifier: Self.processIdentifier(in: output))
        } catch let error as CommandError {
            guard case let .terminated(code, stderr, _) = error else { throw error }
            guard Self.describesAMissingService(code: code, stderr: stderr) else { throw error }
            return nil
        }
    }

    /// The `pid` `launchctl print` reports for the job itself. Only the first
    /// match qualifies: the nested dictionaries that follow it in the report
    /// describe endpoints and spawn records, which carry PIDs of their own.
    ///
    /// A report without one is not a parse failure. It is how launchd describes a
    /// label it holds with no process behind it, which is a state the callers have
    /// to keep apart from a running job rather than round to one.
    private static func processIdentifier(in output: String) -> Int32? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid = ") else { continue }
            return Int32(trimmed.dropFirst("pid = ".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// `launchctl print` exits non-zero both for a service that is not there and
    /// for every other failure, so only the missing-service termination may be
    /// read as "not loaded". Reading the rest that way reports a loaded agent as
    /// absent, which skips the bootout and leaves the bootstrap after it landing
    /// on a live label.
    ///
    /// Matched on the code and the wording together because neither is a
    /// contract: launchctl's status for a missing service is not stable across
    /// macOS versions, and a reworded message under a known code still has to
    /// resolve.
    private static func describesAMissingService(code: Int32, stderr: String) -> Bool {
        code == 113 || code == ESRCH
            || stderr.lowercased().contains("could not find service")
    }
}
