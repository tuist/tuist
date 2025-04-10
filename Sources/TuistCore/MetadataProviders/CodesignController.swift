import Command
import Foundation
import Mockable
import Path

@Mockable
/// Utility to interact with the `codesign` CLI.
public protocol CodesignControlling {
    /// Provides the signature of the XCFramework at the given `xcframeworkPath`, or `nil` if unsigned.
    func codesignSignature(of xcframeworkPath: AbsolutePath) async throws -> String?

    /// Extracts the signature of the XCFramework at the given `xcframeworkPath` into the specified directory.
    func codesignExtractSignature(of xcframeworkPath: AbsolutePath, into directory: AbsolutePath) async throws
}

public final class CodesignController: CodesignControlling {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func codesignSignature(of xcframeworkPath: AbsolutePath) async throws -> String? {
        let (output, error) = await commandRunner.run(
            arguments: [
                "/usr/bin/codesign",
                "-dvv",
                xcframeworkPath.pathString
            ]
        )
        .nonThrowingConcatenatedString()

        if let error {
            if output.contains("code object is not signed at all") {
                return nil
            }
            throw error
        }

        return output
    }

    public func codesignExtractSignature(
        of xcframeworkPath: AbsolutePath,
        into directory: AbsolutePath
    ) async throws {
        _ = try await commandRunner.run(
            arguments: [
                "/usr/bin/codesign",
                "-d",
                "--extract-certificates",
                xcframeworkPath.pathString
            ],
            workingDirectory: directory
        )
        .awaitCompletion()
    }
}
