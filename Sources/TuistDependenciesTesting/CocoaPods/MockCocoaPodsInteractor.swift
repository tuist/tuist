import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod)?
    var invokedSaveParametersList = [(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod)]()
    var stubbedSaveError: Error?

    public func install(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (dependenciesDirectory, method)
        invokedSaveParametersList.append((dependenciesDirectory, method))
        if let error = stubbedSaveError {
            throw error
        }
    }
}
