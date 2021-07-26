import TSCBasic
import TuistCore
import TuistGraph

public protocol CacheArtifactBuilding {
    /// Returns the type of artifact that the concrete builder processes.
    var cacheOutputType: CacheOutputType { get }

    /// Builds a given target and outputs the cacheable artifact into the given directory.
    ///
    /// - Parameters:
    ///   - projectTarget: Build target whether .xcworkspace or .xcodeproj
    ///   - target: Target whose .(xc)framework or bundle will be generated.
    ///   - configuration: The configuration that will be used when compiling the given target.
    ///   - into: The directory into which the output artifacts will be copied.
    func build(projectTarget: XcodeBuildTarget, target: Target, configuration: String, into outputDirectory: AbsolutePath) throws
}
