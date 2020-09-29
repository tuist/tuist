import RxSwift
import TSCBasic
import TuistCore

public protocol ArtifactBuilding {
    /// Returns the type of artifact that the concrete builder processes.
    var artifactType: ArtifactType { get }

    /// Returns an observable build for the given artifact.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - workspacePath: Path to the generated .xcworkspace that contains the given target.
    ///   - target: Target whose artifact will be generated.
    /// - Returns: Path to the compiled .xcframework.
    func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath>

    /// Returns an observable to build an xcframework for the given target.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the generated .xcodeproj that contains the given target.
    ///   - target: Target whose .(xc)framework will be generated.
    /// - Returns: Path to the compiled .xcframework.
    func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath>
}
