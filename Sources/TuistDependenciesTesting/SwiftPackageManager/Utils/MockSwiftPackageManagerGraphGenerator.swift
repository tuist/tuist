import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: (
        (AbsolutePath, [String: TuistGraph.Product], Set<TuistGraph.Platform>, Set<TuistGraph.DeploymentTarget>) throws -> TuistCore.DependenciesGraph
    )?

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>
    ) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, productTypes, platforms, deploymentTargets) ?? .test()
    }
}
