import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((AbsolutePath, Dependencies, String?) throws -> Void)?

    public func fetch(at path: AbsolutePath, dependencies: Dependencies, swiftVersion: String?) throws {
        invokedFetch = true
        try fetchStub?(path, dependencies, swiftVersion)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, Dependencies, String?) throws -> Void)?

    public func update(at path: AbsolutePath, dependencies: Dependencies, swiftVersion: String?) throws {
        invokedUpdate = true
        try updateStub?(path, dependencies, swiftVersion)
    }
}
