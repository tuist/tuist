import TSCBasic
import TSCUtility
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath, [String: Product], Set<TuistGraph.Platform>) throws -> DependenciesGraph)?

    public func generate(at path: AbsolutePath, productTypes: [String: Product], platforms: Set<TuistGraph.Platform>) throws -> DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, productTypes, platforms) ?? .test()
    }
}
