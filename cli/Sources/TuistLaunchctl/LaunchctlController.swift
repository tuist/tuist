import Command
import Foundation
import Mockable
import Path

/// Utility to interact with the `launchctl` CLI.
@Mockable
public protocol LaunchctlControlling {
    /// Loads a LaunchAgent or LaunchDaemon from the given plist path.
    func load(plistPath: AbsolutePath) async throws
    
    /// Unloads a LaunchAgent or LaunchDaemon from the given plist path.
    func unload(plistPath: AbsolutePath) async throws
    
    /// Lists loaded services, optionally filtering by a pattern.
    func list(pattern: String?) async throws -> String
}

public struct LaunchctlController: LaunchctlControlling {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func load(plistPath: AbsolutePath) async throws {
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "load",
                plistPath.pathString,
            ]
        )
        .awaitCompletion()
    }

    public func unload(plistPath: AbsolutePath) async throws {
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "unload",
                plistPath.pathString,
            ]
        )
        .awaitCompletion()
    }

    public func list(pattern: String? = nil) async throws -> String {
        var arguments = ["/bin/launchctl", "list"]
        if let pattern = pattern {
            arguments.append(pattern)
        }
        
        return try await commandRunner.run(arguments: arguments)
            .concatenatedString()
            .trimmingCharacters(in: .whitespaces)
    }
}