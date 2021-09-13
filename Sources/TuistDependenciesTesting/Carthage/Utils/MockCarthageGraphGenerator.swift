import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath) throws -> TuistCore.DependenciesGraph)?

    public func generate(at path: AbsolutePath, for _: Set<TuistGraph.Platform>?) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path) ?? .test()
    }
}
