import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath, Set<TuistGraph.Platform>) throws -> TuistCore.DependenciesGraph)?

    public func generate(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, platforms) ?? .test()
    }
}
