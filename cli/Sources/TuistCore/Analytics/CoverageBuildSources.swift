import Foundation

/// The checkout test products were compiled in, recorded into the `.xctestproducts` bundle by
/// the build. The compiler embeds absolute source paths into the binaries, so coverage from a
/// test run on another machine or checkout names the build's paths, and only the build knows
/// which Git blobs those files had when they were compiled.
public struct CoverageBuildSources: Codable, Equatable, Sendable {
    /// Every spelling of the build's root directory.
    public let rootDirectories: [String]
    /// Git blob ids of the source files, keyed by path relative to the root. Empty when the build
    /// did not run in a Git checkout.
    public let files: [String: String]

    public init(rootDirectories: [String], files: [String: String]) {
        self.rootDirectories = rootDirectories
        self.files = files
    }

    public static let fileName = "tuist_coverage_build.json"
}
