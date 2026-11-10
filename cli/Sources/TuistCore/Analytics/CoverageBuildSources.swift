import Foundation

/// What the build knows about the checkout and the targets a test run's coverage describes,
/// recorded for the run that uses its products (in the same process, or from a
/// `.xctestproducts` bundle in another job).
public struct CoverageBuildSources: Codable, Equatable, Sendable {
    /// Every spelling of the build's root directory.
    public let rootDirectories: [String]
    /// Git blob ids of the source files, keyed by path relative to the root. Empty when the build
    /// did not run in a Git checkout.
    public let files: [String: String]
    /// The targets the tested schemes build, from the project graph: what the coverage export
    /// attributes files to and finds products for, in place of the result bundle's report. Empty
    /// when the build had no graph (`tuist xcodebuild`).
    public let targets: [CoverageBuildTarget]
    /// Each target's coverage prefix map (alias to directory), from the build's intermediates:
    /// what maps the `/^src/…` paths of a prefix-mapped build back to the build's checkout in a
    /// run whose derived data never compiled the products. Empty when the build mapped nothing.
    public let prefixMaps: [String: [String: String]]

    public init(
        rootDirectories: [String],
        files: [String: String],
        targets: [CoverageBuildTarget] = [],
        prefixMaps: [String: [String: String]] = [:]
    ) {
        self.rootDirectories = rootDirectories
        self.files = files
        self.targets = targets
        self.prefixMaps = prefixMaps
    }

    enum CodingKeys: String, CodingKey {
        case rootDirectories, files, targets, prefixMaps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootDirectories = try container.decode([String].self, forKey: .rootDirectories)
        files = try container.decode([String: String].self, forKey: .files)
        targets = try container.decodeIfPresent([CoverageBuildTarget].self, forKey: .targets) ?? []
        prefixMaps = try container.decodeIfPresent([String: [String: String]].self, forKey: .prefixMaps) ?? [:]
    }

    public static let fileName = "tuist_coverage_build.json"
}

/// A target of the tested schemes' build, as the coverage export needs it.
public struct CoverageBuildTarget: Codable, Equatable, Sendable {
    /// A binary the build took from the binary cache rather than compiling: one slice of the
    /// target's xcframework.
    public struct Binary: Codable, Equatable, Sendable {
        public let path: String
        /// The slice's platform as the xcframework names it (`ios`, `macos`, `tvos`, `watchos`,
        /// `xros`) and whether it is the simulator's.
        public let platform: String
        public let simulator: Bool

        public init(path: String, platform: String, simulator: Bool) {
            self.path = path
            self.platform = platform
            self.simulator = simulator
        }
    }

    /// The product's file name (`App.app`, `Lib.framework`, `libLib.a`), which is how xccov
    /// names a target too.
    public let name: String
    public let isTest: Bool
    /// The sources the target compiles, relative to the root when under it.
    public let files: [String]
    /// Empty for a target built from source, whose product is under the build products.
    public let binaries: [Binary]

    public init(name: String, isTest: Bool, files: [String], binaries: [Binary] = []) {
        self.name = name
        self.isTest = isTest
        self.files = files
        self.binaries = binaries
    }
}
