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
        String?,
        Version?,
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
        device: String?,
        osVersion: Version?,
        graphTraverser: GraphTraversing
    ) throws {
        try buildTargetStub?(
            target,
            workspacePath,
            scheme,
            clean,
            configuration,
            buildOutputPath,
            device,
            osVersion,
            graphTraverser
        )
    }
}
