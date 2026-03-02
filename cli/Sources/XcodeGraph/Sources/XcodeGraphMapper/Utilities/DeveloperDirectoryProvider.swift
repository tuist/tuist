import Command
import Foundation
import Path

/// A protocol that obtains the current developer directory (via `xcode-select -p`) asynchronously.
protocol DeveloperDirectoryProviding {
    /// Returns the absolute path to the currently selected Xcode’s Developer directory.
    /// - Throws: If `xcode-select -p` fails or if the output is invalid.
    func developerDirectory() async throws -> AbsolutePath
}

/// Default implementation of `DeveloperDirectoryProviding` that uses `CommandRunner`.
struct DeveloperDirectoryProvider: DeveloperDirectoryProviding {
    private let commandRunner: CommandRunning

    /// Creates a new provider that uses the given `CommandRunning` instance.
    /// - Parameter commandRunner: By default, uses `CommandRunner()`.
    init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Uses `xcode-select -p` to get the path to the currently selected Xcode’s Developer folder.
    /// - Throws: If `xcode-select -p` fails or if the path output is invalid.
    /// - Returns: A valid `AbsolutePath` pointing to the developer directory.
    func developerDirectory() async throws -> AbsolutePath {
        let stream = commandRunner.run(arguments: ["xcode-select", "-p"])
        let rawPath = try await stream.concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return try AbsolutePath(validating: rawPath)
    }
}
