import TSCBasic
import TSCUtility
import TuistAutomation
import TuistCore
import TuistGraph

public final class MockTargetBuilder: TargetBuilding {
    public init() {}

    public var buildTargetStub: ((
        GraphTarget,
        AbsolutePath,
        Scheme,
        Bool,
        String?,
        AbsolutePath?,
        AbsolutePath?,
        String?,
        Version?,
        Bool,
        GraphTraversing
    ) throws -> Void)?

    public func buildTarget(
        _ target: GraphTarget,
        platform _: TuistGraph.Platform,
        workspacePath: AbsolutePath,
        scheme: Scheme,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        device: String?,
        osVersion: Version?,
        rosetta: Bool,
        graphTraverser: GraphTraversing
    ) throws {
        try buildTargetStub?(
            target,
            workspacePath,
            scheme,
            clean,
            configuration,
            buildOutputPath,
            derivedDataPath,
            device,
            osVersion,
            rosetta,
            graphTraverser
        )
    }
}
