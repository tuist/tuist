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

    public var buildableEntrySchemesStub: ((Graph) -> [Scheme])?
    public func buildableEntrySchemes(graph: Graph) -> [Scheme] {
        buildableEntrySchemesStub?(graph) ?? []
    }

    public var buildArgumentsStub: ((Target, String?, Bool) -> [XcodeBuildArgument])?
    public func buildArguments(target: Target, configuration: String?, skipSigning: Bool) -> [XcodeBuildArgument] {
        if let buildArgumentsStub = buildArgumentsStub {
            return buildArgumentsStub(target, configuration, skipSigning)
        } else {
            return []
        }
    }

    public var testableTargetStub: ((Scheme, Graph) -> Target?)?
    public func testableTarget(scheme: Scheme, graph: Graph) -> Target? {
        if let testableTargetStub = testableTargetStub {
            return testableTargetStub(scheme, graph)
        } else {
            return Target.test()
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
}
