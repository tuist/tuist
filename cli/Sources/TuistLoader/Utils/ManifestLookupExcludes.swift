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
    ]

    /// Runs a glob traversal that prunes the given `exclude` patterns during descent.
    ///
    /// Wraps `Glob.search` directly because `FileSysteming.glob` does not yet expose an `exclude:` parameter.
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
        .eraseToAnyThrowingAsyncSequenceable()
    }
}
