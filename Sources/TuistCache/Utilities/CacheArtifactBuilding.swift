import TSCBasic
import TuistCore
import TuistGraph

public protocol CacheArtifactBuilding {
    /// Returns the type of artifact that the concrete builder processes.
    var cacheOutputType: CacheOutputType { get }

    /// Builds a given target and outputs the cacheable artifact into the given directory.
    ///
    /// - Parameters:
    ///   - workspacePath: Path to the generated .xcworkspace that contains the given target.
    ///   - target: Target whose artifact will be generated.
    ///   - configuration: The configuration that will be used when compiling the given target.
    ///   - into: The directory into which the output artifacts will be copied.
    func build(workspacePath: AbsolutePath, target: Target, configuration: String?, into outputDirectory: AbsolutePath) throws

    /// Builds a given target and outputs the cacheable artifact into the given directory.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the generated .xcodeproj that contains the given target.
    ///   - target: Target whose .(xc)framework will be generated.
    ///   - configuration: The configuration that will be used when compiling the given target.
    ///   - into: The directory into which the output artifacts will be copied.
    func build(projectPath: AbsolutePath, target: Target, configuration: String?, into outputDirectory: AbsolutePath) throws
}
