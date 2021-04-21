import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: FetchParameters?
    var invokedFetchParametersList = [FetchParameters]()
    var stubbedFetchError: Error?

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
        invokedFetchCount += 1
        invokedFetchParameters = parameters
        invokedFetchParametersList.append(parameters)
        if let error = stubbedFetchError {
            throw error
        }
    }

    var invokedUpdate = false
    var invokedUpdateCount = 0
    var invokedUpdateParameters: UpdateParameters?
    var invokedUpdateParametersList = [UpdateParameters]()
    var stubbedUpdateError: Error?

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
        invokedUpdateCount += 1
        invokedUpdateParameters = parameters
        invokedUpdateParametersList.append(parameters)
        if let error = stubbedUpdateError {
            throw error
        }
    }

    var invokedClean = false
    var invokedCleanCount = 0
    var invokedCleanParameters: AbsolutePath?
    var invokedCleanParametersList = [AbsolutePath]()
    var stubbedCleanError: Error?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        invokedCleanCount += 1
        invokedCleanParameters = dependenciesDirectory
        invokedCleanParametersList.append(dependenciesDirectory)
        if let error = stubbedCleanError {
            throw error
        }
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
