import Foundation
import Path

/// A protocol that obtains the current developer directory (via `xcode-select -p`) asynchronously.
protocol DeveloperDirectoryProviding {
    /// Returns the absolute path to the currently selected Xcode’s Developer directory.
    /// - Throws: If `xcode-select -p` fails or if the output is invalid.
    func developerDirectory() async throws -> AbsolutePath
}

/// Default implementation of `DeveloperDirectoryProviding` that invokes `xcode-select`.
struct DeveloperDirectoryProvider: DeveloperDirectoryProviding {
    /// Uses `xcode-select -p` to get the path to the currently selected Xcode’s Developer folder.
    /// - Throws: If `xcode-select -p` fails or if the path output is invalid.
    /// - Returns: A valid `AbsolutePath` pointing to the developer directory.
    func developerDirectory() async throws -> AbsolutePath {
        let rawPath = try await SubprocessRunner.capture(arguments: ["xcode-select", "-p"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return try AbsolutePath(validating: rawPath)
    }
}
