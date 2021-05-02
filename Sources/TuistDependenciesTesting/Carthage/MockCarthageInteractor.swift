import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((AbsolutePath, CarthageDependencies, Set<Platform>) throws -> Void)?

    public func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: CarthageDependencies,
        platforms: Set<Platform>
    ) throws {
        invokedFetch = true
        try fetchStub?(dependenciesDirectory, dependencies, platforms)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, CarthageDependencies, Set<Platform>) throws -> Void)?

    public func update(
        dependenciesDirectory: AbsolutePath,
        dependencies: CarthageDependencies,
        platforms: Set<Platform>
    ) throws {
        invokedUpdate = true
        try updateStub?(dependenciesDirectory, dependencies, platforms)
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
