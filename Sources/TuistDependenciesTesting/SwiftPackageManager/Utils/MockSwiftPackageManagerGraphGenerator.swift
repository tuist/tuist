import TSCBasic
import TSCUtility
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath, [String: TuistGraph.Product], Set<TuistGraph.Platform>) throws -> TuistDependencies.DependenciesGraph)?

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>
    ) throws -> TuistDependencies.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, productTypes, platforms) ?? .test()
    }
}
