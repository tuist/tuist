import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (dependenciesDirectoryPath: AbsolutePath, method: InstallDependenciesMethod)?
    var invokedSaveParametersList = [(dependenciesDirectoryPath: AbsolutePath, method: InstallDependenciesMethod)]()
    var stubbedSaveError: Error?

    public func install(dependenciesDirectoryPath: AbsolutePath, method: InstallDependenciesMethod) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (dependenciesDirectoryPath, method)
        invokedSaveParametersList.append((dependenciesDirectoryPath, method))
        if let error = stubbedSaveError {
            throw error
        }
    }
}
