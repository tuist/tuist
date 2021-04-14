import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    var invokedFetch = false
    var invokedFetchCount = 0
    var invokedFetchParameters: AbsolutePath?
    var invokedFetchParametersList = [AbsolutePath]()
    var stubbedFetchError: Error?

    public func fetch(dependenciesDirectory: AbsolutePath) throws {
        invokedFetch = true
        invokedFetchCount += 1
        invokedFetchParameters = dependenciesDirectory
        invokedFetchParametersList.append(dependenciesDirectory)
        if let error = stubbedFetchError {
            throw error
        }
    }
}
