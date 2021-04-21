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
        dependencies: SwiftPackageManagerDependencies
    ) throws {
        let parameters = FetchParameters(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies
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
        dependencies: SwiftPackageManagerDependencies
    ) throws {
        let parameters = UpdateParameters(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies
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
