import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: (dependenciesDirectory: AbsolutePath, dependencies: CarthageDependencies)?
    var invokedFetchParametersList = [(dependenciesDirectory: AbsolutePath, dependencies: CarthageDependencies)]()
    var stubbedFetchError: Error?

    public func fetch(dependenciesDirectory: AbsolutePath, dependencies: CarthageDependencies) throws {
        invokedFetch = true
        invokedFetchCount += 1
        invokedFetchParameters = (dependenciesDirectory, dependencies)
        invokedFetchParametersList.append((dependenciesDirectory, dependencies))
        if let error = stubbedFetchError {
            throw error
        }
    }
}
