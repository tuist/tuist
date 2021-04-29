import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((FetchParameters) throws -> Void)?

    public func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: CarthageDependencies,
        platforms: Set<Platform>
    ) throws {
        let parameters = FetchParameters(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            platforms: platforms
        )

        invokedFetch = true
        try fetchStub?(parameters)
    }

    var invokedUpdate = false
    var updateStub: ((UpdateParameters) throws -> Void)?

    public func update(
        dependenciesDirectory: AbsolutePath,
        dependencies: CarthageDependencies,
        platforms: Set<Platform>
    ) throws {
        let parameters = UpdateParameters(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            platforms: platforms
        )

        invokedUpdate = true
        try updateStub?(parameters)
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}

// MARK: - Models

extension MockCarthageInteractor {
    struct FetchParameters {
        let dependenciesDirectory: AbsolutePath
        let dependencies: CarthageDependencies
        let platforms: Set<Platform>
    }

    struct UpdateParameters {
        let dependenciesDirectory: AbsolutePath
        let dependencies: CarthageDependencies
        let platforms: Set<Platform>
    }
}
