import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: (dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies)?
    var invokedFetchParametersList = [(dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies)]()
    var stubbedFetchError: Error?

    public func fetch(dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies) throws {
        invokedFetch = true
        invokedFetchCount += 1
        invokedFetchParameters = (dependenciesDirectory, dependencies)
        invokedFetchParametersList.append((dependenciesDirectory, dependencies))
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
        invokedCleanParameters = (dependenciesDirectory)
        invokedCleanParametersList.append((dependenciesDirectory))
        if let error = stubbedCleanError {
            throw error
        }
    }
}
