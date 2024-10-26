import FileSystem
import Foundation
import Path

extension FileSysteming {
    /// Returns the list of paths that match the given glob pattern, if the directory exists.
    ///
    /// - Parameters:
    ///   - directory: Base absolute directory that glob patterns are relative to.
    ///   - include: A list of glob patterns.
    /// - Throws: an error if the directory where the first glob pattern is declared doesn't exist
    /// - Returns: An async sequence to get the results.
    public func throwingGlob(
        directory: Path.AbsolutePath,
        include: [String]
    ) async throws -> AnyThrowingAsyncSequenceable<AbsolutePath> {
        for include in include {
            try await validateGlobPattern(for: directory, include: include)
        }

        return try glob(directory: directory, include: include)
    }

    private func validateGlobPattern(
        for directory: AbsolutePath,
        include: String
    ) async throws {
        let globPath = directory.appending(try RelativePath(validating: include)).pathString

        if globPath.isGlobComponent {
            let pathUpToLastNonGlob = try AbsolutePath(validating: globPath).upToLastNonGlob

            if try await !exists(pathUpToLastNonGlob, isDirectory: true) {
                let invalidGlob = InvalidGlob(
                    pattern: globPath,
                    nonExistentPath: pathUpToLastNonGlob
                )
                throw GlobError.nonExistentDirectory(invalidGlob)
            }
        }
    }
}
