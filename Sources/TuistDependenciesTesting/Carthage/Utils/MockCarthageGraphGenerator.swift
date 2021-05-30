import TSCBasic
import TSCUtility
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}
    
    var invokedGenerate = false
    var generateStub: ((AbsolutePath) throws -> DependenciesGraph)?
    
    public func generate(at path: AbsolutePath) throws -> DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path) ?? .test()
    }
}
