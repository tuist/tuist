import ProjectDescription
import TSCBasic
import TSCUtility

@testable import TuistDependencies

public final class MockCarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath) throws -> ProjectDescription.DependenciesGraph)?

    public func generate(at path: AbsolutePath) throws -> ProjectDescription.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path) ?? .test()
    }
}
