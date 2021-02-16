import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph

@testable import TuistAutomation

public final class MockBuildGraphInspector: BuildGraphInspecting {
    public init() {}
    public var workspacePathStub: ((AbsolutePath) -> AbsolutePath?)?
    public func workspacePath(directory: AbsolutePath) -> AbsolutePath? {
        workspacePathStub?(directory) ?? directory
    }

    public var buildableTargetStub: ((Scheme, Graph) -> (Project, Target)?)?
    public func buildableTarget(scheme: Scheme, graph: Graph) -> (Project, Target)? {
        if let buildableTargetStub = buildableTargetStub {
            return buildableTargetStub(scheme, graph)
        } else {
            return (Project.test(), Target.test())
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

    public var buildableEntrySchemesStub: ((Graph) -> [Scheme])?
    public func buildableEntrySchemes(graph: Graph) -> [Scheme] {
        buildableEntrySchemesStub?(graph) ?? []
    }

    public var buildArgumentsStub: ((Project, Target, String?, Bool) -> [XcodeBuildArgument])?
    public func buildArguments(project: Project, target: Target, configuration: String?, skipSigning: Bool) -> [XcodeBuildArgument] {
        if let buildArgumentsStub = buildArgumentsStub {
            return buildArgumentsStub(project, target, configuration, skipSigning)
        } else {
            return []
        }
    }

    public var testableTargetStub: ((Scheme, Graph) -> TargetNode?)?
    public func testableTarget(scheme: Scheme, graph: Graph) -> TargetNode? {
        if let testableTargetStub = testableTargetStub {
            return testableTargetStub(scheme, graph)
        } else {
            return TargetNode.test()
        }
    }

    public var testableSchemesStub: ((Graph) -> [Scheme])?
    public func testableSchemes(graph: Graph) -> [Scheme] {
        if let testableSchemesStub = testableSchemesStub {
            return testableSchemesStub(graph)
        } else {
            return []
        }
    }

    public var testSchemesStub: ((Graph) -> [Scheme])?
    public func testSchemes(graph: Graph) -> [Scheme] {
        testSchemesStub?(graph) ?? []
    }

    public var projectSchemesStub: ((Graph) -> [Scheme])?
    public func projectSchemes(graph: Graph) -> [Scheme] {
        projectSchemesStub?(graph) ?? []
    }
}
