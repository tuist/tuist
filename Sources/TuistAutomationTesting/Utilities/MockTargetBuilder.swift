import TSCBasic
import TuistAutomation
import TuistCore
import TuistGraph

public final class MockTargetBuilder: TargetBuilding {
    public init() {}

    public var buildTargetStub: ((GraphTarget, AbsolutePath, String, Bool, String?, AbsolutePath?) throws -> Void)?
    public func buildTarget(
        _ target: GraphTarget,
        workspacePath: AbsolutePath,
        schemeName: String,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?
    ) throws {
        try buildTargetStub?(target, workspacePath, schemeName, clean, configuration, buildOutputPath)
    }
}
