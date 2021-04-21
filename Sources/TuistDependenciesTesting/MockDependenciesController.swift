import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}

    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: (path: AbsolutePath, dependencies: Dependencies)?
    var invokedFetchParametersList = [(path: AbsolutePath, dependencies: Dependencies)]()
    var stubbedFetchError: Error?

    public func fetch(at path: AbsolutePath, dependencies: Dependencies) throws {
        invokedFetch = true
        invokedFetchCount += 1
        invokedFetchParameters = (path, dependencies)
        invokedFetchParametersList.append((path, dependencies))
        if let error = stubbedFetchError {
            throw error
        }
    }
    
    var invokedUpdate = false
    var invokedUpdateCount = 0
    var invokedUpdateParameters: (path: AbsolutePath, dependencies: Dependencies)?
    var invokedUpdateParametersList = [(path: AbsolutePath, dependencies: Dependencies)]()
    var stubbedUpdateError: Error?

    public func update(at path: AbsolutePath, dependencies: Dependencies) throws {
        invokedUpdate = true
        invokedUpdateCount += 1
        invokedUpdateParameters = (path, dependencies)
        invokedUpdateParametersList.append((path, dependencies))
        if let error = stubbedUpdateError {
            throw error
        }
    }
}
