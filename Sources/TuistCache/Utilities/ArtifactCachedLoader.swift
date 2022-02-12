import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public protocol ArtifactLoading {
    /// Reads an artifact and returns its in-memory representation.
    /// It can be a`GraphDependency.framework`, `GraphDependency.xcframework` or `GraphDependency.bundle`.
    /// - Parameter path: Path to the artifact.
    func load(path: AbsolutePath) throws -> GraphDependency
}

class ArtifactCachedLoader: ArtifactLoading {
    var loadedPrecompiledArtifacts = [AbsolutePath: GraphDependency]()

    /// Utility to parse an .xcframework from the filesystem and load it into memory.
    private let xcframeworkLoader: XCFrameworkLoading

    /// Utility to parse a .framework from the filesystem and load it into memory.
    private let frameworkLoader: FrameworkLoading

    /// Utility to parse a .bundle from the filesystem and load it into memory.
    private let bundleLoader: BundleLoading

    /// Initializes the loader with its attributes.
    /// - Parameter frameworkLoader: Utility to parse an .framework from the filesystem and load it into memory.
    /// - Parameter xcframeworkLoader: Utility to parse an .xcframework from the filesystem and load it into memory.
    /// - Parameter bundleLoader: Utility to parse an .bundle from the filesystem and load it into memory.
    init(frameworkLoader: FrameworkLoading = FrameworkLoader(),
         xcframeworkLoader: XCFrameworkLoading = XCFrameworkLoader(),
         bundleLoader: BundleLoading = BundleLoader())
    {
        self.frameworkLoader = frameworkLoader
        self.xcframeworkLoader = xcframeworkLoader
        self.bundleLoader = bundleLoader
    }

    func load(path: AbsolutePath) throws -> GraphDependency {
        if let cachedArtifact = loadedPrecompiledArtifacts[path] {
            return cachedArtifact
        } else if let framework = try? frameworkLoader.load(path: path) {
            loadedPrecompiledArtifacts[path] = framework
            return framework
        } else if let xcframework = try? xcframeworkLoader.load(path: path) {
            loadedPrecompiledArtifacts[path] = xcframework
            return xcframework
        } else {
            let bundle = try bundleLoader.load(path: path)
            loadedPrecompiledArtifacts[path] = bundle
            return bundle
        }
    }
}
