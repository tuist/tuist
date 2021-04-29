import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((AbsolutePath, Dependencies) throws -> Void)?

    public func fetch(at path: AbsolutePath, dependencies: Dependencies) throws {
        invokedFetch = true
        try fetchStub?(path, dependencies)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, Dependencies) throws -> Void)?

    public func update(at path: AbsolutePath, dependencies: Dependencies) throws {
        invokedUpdate = true
        try updateStub?(path, dependencies)
    }
}
