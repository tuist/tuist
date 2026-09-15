import TuistConstants

enum ManifestLookupExcludes {
    /// Glob patterns that prune the derived directories preserved across generations from recursive manifest lookups.
    ///
    /// `Derived/FrameworkSearchPaths` holds one symbolic link per precompiled framework, pointing into the binary
    /// cache. Manifests are never generated there, and following those links descends into every cached framework
    /// tree, which on large graphs dominates the time spent loading the workspace.
    static let derivedDirectories = Constants.DerivedDirectory.preservedAcrossGenerations.map {
        "**/\(Constants.DerivedDirectory.name)/\($0)"
    }
}
