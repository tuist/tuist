import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph

public protocol CacheArtifactBuilding {
    /// Returns the type of artifact that the concrete builder processes.
    var cacheOutputType: CacheOutputType { get }

    /// Builds a given target and outputs the cacheable artifact into the given directory.
    ///
    /// - Parameters:
    ///   - projectTarget: Build target whether .xcworkspace or .xcodeproj
    ///   - configuration: The configuration that will be used when compiling the given target.
    ///   - osVersion: The specific version of the OS that will be used when compiling the given target.
    ///   - deviceName: The specific device that will be used when compiling the given target.
    ///   - into: The directory into which the output artifacts will be copied.
    func build(
        graph: Graph,
        scheme: Scheme,
        projectTarget: XcodeBuildTarget,
        configuration: String,
        osVersion: Version?,
        deviceName: String?,
        into outputDirectory: AbsolutePath
    ) async throws
}

extension CacheArtifactBuilding {
    func platform(scheme: Scheme) -> Platform {
        Platform.allCases.first { scheme.name.hasSuffix($0.caseValue) }!
    }
}
