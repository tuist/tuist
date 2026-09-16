import FileSystem
import Foundation
import Glob
import Path
import TuistConstants

enum ManifestLookupExcludes {
    /// Glob patterns that prune `Derived/FrameworkSearchPaths` from recursive manifest lookups.
    ///
    /// The directory holds one symbolic link per precompiled framework, pointing into the binary cache. Manifests are
    /// never generated there, and following those links descends into every cached framework tree, which on large
    /// graphs dominates the time spent looking manifests up.
    static let frameworkSearchPathLinks = [
        "**/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.frameworkSearchPaths)",
        "**/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.frameworkSearchPaths)/**",
    ]

    /// Runs a glob traversal and drops paths that match any `exclude` pattern.
    ///
    /// Delegates the walk to `Glob.search` so the include-pattern base extraction and symlink handling stay in one
    /// place. `Glob.search` only evaluates its own `exclude` for paths that already satisfy `include`, so it cannot
    /// short-circuit descent into an intermediate directory. Filtering here ensures manifests that live behind a
    /// pruned prefix are never returned to the caller.
    static func glob(
        directory: AbsolutePath,
        include: [String],
        exclude: [String]
    ) throws -> AnyThrowingAsyncSequenceable<AbsolutePath> {
        let encodedPath = directory.pathString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? directory.pathString
        let baseURL = URL(string: encodedPath)!
        let includePatterns = try include.map { try Pattern($0) }
        let excludePatterns = try exclude.map { try Pattern($0) }

        return Glob.search(
            directory: baseURL,
            include: includePatterns,
            exclude: excludePatterns,
            skipHiddenFiles: false
        )
        .map { url -> AbsolutePath in
            let path = url.absoluteString.removingPercentEncoding ?? url.absoluteString
            return try AbsolutePath(validating: path)
        }
        .filter { path in
            let pathString = path.pathString
            return !excludePatterns.contains(where: { $0.match(pathString) })
        }
        .eraseToAnyThrowingAsyncSequenceable()
    }
}
