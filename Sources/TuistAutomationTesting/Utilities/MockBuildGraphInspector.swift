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

    public var buildableTargetStub: ((Scheme, GraphTraversing) -> (Project, Target)?)?
    public func buildableTarget(scheme: Scheme, graphTraverser: GraphTraversing) -> (Project, Target)? {
        if let buildableTargetStub = buildableTargetStub {
            return buildableTargetStub(scheme, graphTraverser)
        } else {
            return (Project.test(), Target.test())
        }
    }

    public var buildableSchemesStub: ((GraphTraversing) -> [Scheme])?
    public func buildableSchemes(graphTraverser: GraphTraversing) -> [Scheme] {
        if let buildableSchemesStub = buildableSchemesStub {
            return buildableSchemesStub(graphTraverser)
        } else {
            return []
        }
    }

    public var buildableEntrySchemesStub: ((GraphTraversing) -> [Scheme])?
    public func buildableEntrySchemes(graphTraverser: GraphTraversing) -> [Scheme] {
        buildableEntrySchemesStub?(graphTraverser) ?? []
    }

    public var buildArgumentsStub: ((Project, Target, String?, Bool) -> [XcodeBuildArgument])?
    public func buildArguments(project: Project, target: Target, configuration: String?, skipSigning: Bool) -> [XcodeBuildArgument] {
        if let buildArgumentsStub = buildArgumentsStub {
            return buildArgumentsStub(project, target, configuration, skipSigning)
        } else {
            return []
        }
    }

    public var testableTargetStub: ((Scheme, GraphTraversing) -> ValueGraphTarget?)?
    public func testableTarget(scheme: Scheme, graphTraverser: GraphTraversing) -> ValueGraphTarget? {
        if let testableTargetStub = testableTargetStub {
            return testableTargetStub(scheme, graphTraverser)
        } else {
            return ValueGraphTarget.test()
        }
    }

    public var testableSchemesStub: ((GraphTraversing) -> [Scheme])?
    public func testableSchemes(graphTraverser: GraphTraversing) -> [Scheme] {
        if let testableSchemesStub = testableSchemesStub {
            return testableSchemesStub(graphTraverser)
        } else {
            return []
        }
    }

    public var testSchemesStub: ((GraphTraversing) -> [Scheme])?
    public func testSchemes(graphTraverser: GraphTraversing) -> [Scheme] {
        testSchemesStub?(graphTraverser) ?? []
    }

    public var projectSchemesStub: ((GraphTraversing) -> [Scheme])?
    public func projectSchemes(graphTraverser: GraphTraversing) -> [Scheme] {
        projectSchemesStub?(graphTraverser) ?? []
    }
}
