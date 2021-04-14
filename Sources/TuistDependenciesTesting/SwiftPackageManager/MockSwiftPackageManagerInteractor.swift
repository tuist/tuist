import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: FetchParameters?
    var invokedFetchParametersList = [FetchParameters]()
    var stubbedFetchError: Error?

    public func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
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

extension MockSwiftPackageManagerInteractor {
    struct FetchParameters {
        let dependenciesDirectory: AbsolutePath
        let dependencies: SwiftPackageManagerDependencies
        let platforms: Set<Platform>
    }
}
