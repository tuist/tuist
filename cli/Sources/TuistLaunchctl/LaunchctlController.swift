import Command
import Foundation
import Mockable
import Path

/// Utility to interact with the `launchctl` CLI.
@Mockable
public protocol LaunchctlControlling {
    /// Bootstraps a LaunchAgent from the given plist path into the current user's GUI domain.
    func bootstrap(plistPath: AbsolutePath) async throws

    /// Boots out a LaunchAgent by label from the current user's GUI domain.
    func bootout(label: String) async throws

    /// Restarts a LaunchAgent by label in the current user's GUI domain.
    func kickstart(label: String) async throws

    /// Returns whether a LaunchAgent with the given label is currently loaded in the
    /// current user's GUI domain.
    func isLoaded(label: String) async throws -> Bool
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

    public func isLoaded(label: String) async throws -> Bool {
        let uid = getuid()
        do {
            _ = try await commandRunner.run(
                arguments: [
                    "/bin/launchctl",
                    "print",
                    "gui/\(uid)/\(label)",
                ]
            )
            .awaitCompletion()
            return true
        } catch let error as CommandError {
            guard case let .terminated(code, stderr, _) = error else { throw error }
            guard Self.describesAMissingService(code: code, stderr: stderr) else { throw error }
            return false
        }
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
