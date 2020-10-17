import TSCBasic
@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}
    
    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: AbsolutePath?
    var invokedFetchParametersList = [AbsolutePath]()
    var stubbedFetchError: Error?
    
    public func fetch(at path: AbsolutePath) throws {
        invokedFetch = true
        invokedFetchCount += 1
        invokedFetchParameters = path
        invokedFetchParametersList.append(path)
        if let error = stubbedFetchError {
            throw error
        }
    }
    
    var invokedUpdate = false
    var invokedUpdateCount = 0
    var invokedUpdateParameters: AbsolutePath?
    var invokedUpdateParametersList = [AbsolutePath]()
    var stubbedUpdateError: Error?
    
    public func update(at path: AbsolutePath) throws {
        invokedUpdate = true
        invokedUpdateCount += 1
        invokedUpdateParameters = path
        invokedUpdateParametersList.append(path)
        if let error = stubbedUpdateError {
            throw error
        }
    }
}
