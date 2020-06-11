import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting

@testable import TuistAutomation

public final class MockBuildGraphInspector: BuildGraphInspecting {
    public init() {}
    public var workspacePathStub: ((AbsolutePath) -> AbsolutePath?)?
    public func workspacePath(directory: AbsolutePath) -> AbsolutePath? {
        workspacePathStub?(directory) ?? nil
    }

    public var buildableTargetStub: ((Scheme, Graph) -> Target?)?
    public func buildableTarget(scheme: Scheme, graph: Graph) -> Target? {
        if let buildableTargetStub = buildableTargetStub {
            return buildableTargetStub(scheme, graph)
        } else {
            return Target.test()
        }
    }

    public var buildableSchemesStub: ((Graph) -> [Scheme])?
    public func buildableSchemes(graph: Graph) -> [Scheme] {
        if let buildableSchemesStub = buildableSchemesStub {
            return buildableSchemesStub(graph)
        } else {
            return []
        }
    }

    public var buildArgumentsStub: ((Target, String?) -> [XcodeBuildArgument])?
    public func buildArguments(target: Target, configuration: String?) -> [XcodeBuildArgument] {
        if let buildArgumentsStub = buildArgumentsStub {
            return buildArgumentsStub(target, configuration)
        } else {
            return []
        }
    }
}
