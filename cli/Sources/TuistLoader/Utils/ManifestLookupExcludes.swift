import TuistConstants

enum ManifestLookupExcludes {
    /// Glob patterns that prune `Derived/FrameworkSearchPaths` from recursive manifest lookups.
    ///
    /// The directory holds one symbolic link per precompiled framework, pointing into the binary cache. Manifests are
    /// never generated there, and following those links descends into every cached framework tree, which on large
    /// graphs dominates the time spent looking manifests up. `FileSysteming.glob(directory:include:exclude:)` (added
    /// in tuist.FileSystem 0.19.1) evaluates `exclude` before `include`, so the pattern below prunes descent at the
    /// directory boundary rather than filtering after the walk.
    static let frameworkSearchPathLinks = [
        "**/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.frameworkSearchPaths)",
    ]
}
