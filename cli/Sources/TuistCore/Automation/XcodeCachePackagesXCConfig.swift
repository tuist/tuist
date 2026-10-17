import Path

/// The xcconfig that applies a workspace's Xcode cache prefix mappings to the targets Xcode
/// builds from `Project.packages`.
///
/// Those targets come from the package manifests, not from the generated projects, so they
/// never read the projects' build settings. Settings passed to `xcodebuild` through
/// `-xcconfig` or `XCODE_XCCONFIG_FILE` reach every target in the build instead.
public enum XcodeCachePackagesXCConfig {
    /// The location of the xcconfig inside a generated `.xcworkspace`.
    public static func path(xcWorkspacePath: AbsolutePath) -> AbsolutePath {
        xcWorkspacePath.appending(components: "xcshareddata", "tuist", "xcode-cache.xcconfig")
    }
}
