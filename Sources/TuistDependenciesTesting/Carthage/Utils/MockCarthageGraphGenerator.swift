import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore

@testable import TuistDependencies

public final class MockCarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: ((AbsolutePath) throws -> TuistCore.DependenciesGraph)?

    public func generate(at path: AbsolutePath) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path) ?? .test()
    }
}
