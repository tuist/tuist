import Command
import Foundation
import Mockable
import Path

/// Utility to interact with the `codesign` CLI.
@Mockable
public protocol CodesignControlling {
    /// Provides the signature of the XCFramework at the given `xcframeworkPath`, or `nil` if unsigned.
    func signature(of xcframeworkPath: AbsolutePath) async throws -> String?

    /// Extracts the signature of the XCFramework at the given `xcframeworkPath` into the specified directory.
    func extractSignature(of xcframeworkPath: AbsolutePath, into directory: AbsolutePath) async throws
}

public struct CodesignController: CodesignControlling {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func signature(of xcframeworkPath: AbsolutePath) async throws -> String? {
        do {
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/codesign",
                    "-dvv",
                    xcframeworkPath.pathString,
                ]
            )
            .concatenatedString()
            .trimmingCharacters(in: .whitespaces)
        } catch let error as CommandError {
            if case let .terminated(_, stdErr) = error, stdErr.contains("code object is not signed at all") {
                return nil
            } else {
                throw error
            }
        }
    }

    public func extractSignature(
        of xcframeworkPath: AbsolutePath,
        into directory: AbsolutePath
    ) async throws {
        _ = try await commandRunner.run(
            arguments: [
                "/usr/bin/codesign",
                "-d",
                "--extract-certificates",
                xcframeworkPath.pathString,
            ],
            workingDirectory: directory
        )
        .awaitCompletion()
    }
}
