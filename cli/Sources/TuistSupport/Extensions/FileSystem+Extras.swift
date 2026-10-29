import FileSystem
import Foundation
import Path
import TuistConstants

public enum ManifestLookupExcludes {
    /// Glob patterns that prune `Derived/FrameworkSearchPaths` from lookups over a project tree.
    ///
    /// The directory holds one symbolic link per precompiled framework, pointing into the binary cache. Nothing a
    /// manifest declares lives there, and following those links descends into every cached framework tree, which on
    /// large graphs dominates the time spent loading them. `FileSysteming.glob(directory:include:exclude:)` evaluates
    /// `exclude` before `include`, so the pattern prunes descent at the directory boundary rather than filtering after
    /// the walk.
    public static let frameworkSearchPathLinks = [
        "**/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.frameworkSearchPaths)",
    ]
}

extension FileSysteming {
    /// Expands glob patterns declared in a manifest (sources, resources, files, buildable folders, …) without descending
    /// into `Derived/FrameworkSearchPaths`. See ``ManifestLookupExcludes/frameworkSearchPathLinks``.
    public func manifestGlob(
        directory: Path.AbsolutePath,
        include: [String]
    ) throws -> AnyThrowingAsyncSequenceable<AbsolutePath> {
        try glob(directory: directory, include: include, exclude: ManifestLookupExcludes.frameworkSearchPathLinks)
    }

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

        return try manifestGlob(directory: directory, include: include)
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
