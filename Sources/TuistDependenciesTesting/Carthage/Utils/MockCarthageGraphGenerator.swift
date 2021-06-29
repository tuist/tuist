import ProjectDescription
import TSCBasic
import TSCUtility

@testable import TuistDependencies

public final class MockCarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath) throws -> TuistDependencies.DependenciesGraph)?

    public func generate(at path: AbsolutePath) throws -> TuistDependencies.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path) ?? .test()
    }
}
