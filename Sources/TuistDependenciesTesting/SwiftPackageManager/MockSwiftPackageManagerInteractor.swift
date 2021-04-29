import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((FetchParameters) throws -> Void)?

    public func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies
    ) throws {
        let parameters = FetchParameters(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies
        )

        invokedFetch = true
        try fetchStub?(parameters)
    }

    var invokedUpdate = false
    var updateStub: ((UpdateParameters) throws -> Void)?

    public func update(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies
    ) throws {
        let parameters = UpdateParameters(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies
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

extension MockSwiftPackageManagerInteractor {
    struct FetchParameters {
        let dependenciesDirectory: AbsolutePath
        let dependencies: SwiftPackageManagerDependencies
    }

    struct UpdateParameters {
        let dependenciesDirectory: AbsolutePath
        let dependencies: SwiftPackageManagerDependencies
    }
}
