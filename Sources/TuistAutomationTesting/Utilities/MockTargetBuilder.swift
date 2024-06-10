import Path
import TSCUtility
import TuistAutomation
import TuistCore
import XcodeGraph

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
        XcodeGraph.Version?,
        Bool,
        GraphTraversing,
        [String]
    ) throws -> Void)?

    public func buildTarget(
        _ target: GraphTarget,
        platform _: XcodeGraph.Platform,
        workspacePath: AbsolutePath,
        scheme: Scheme,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        device: String?,
        osVersion: XcodeGraph.Version?,
        rosetta: Bool,
        graphTraverser: GraphTraversing,
        passthroughXcodeBuildArguments: [String]
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
            graphTraverser,
            passthroughXcodeBuildArguments
        )
    }
}
