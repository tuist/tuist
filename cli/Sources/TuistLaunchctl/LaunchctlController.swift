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
            if case .terminated = error {
                return false
            }
            throw error
        }
    }
}
