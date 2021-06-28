import ProjectDescription
import TSCBasic
import TSCUtility
import TuistGraph
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath, [String: TuistGraph.Product], Set<TuistGraph.Platform>) throws -> ProjectDescription.DependenciesGraph)?

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>
    ) throws -> ProjectDescription.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, productTypes, platforms) ?? .test()
    }
}
