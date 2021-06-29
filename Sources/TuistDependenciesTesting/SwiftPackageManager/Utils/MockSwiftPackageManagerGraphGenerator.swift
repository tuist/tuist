import ProjectDescription
import TSCBasic
import TSCUtility
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath, Set<TuistGraph.Platform>) throws -> TuistDependencies.DependenciesGraph)?

    public func generate(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>) throws -> TuistDependencies.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, platforms) ?? .test()
    }
}
