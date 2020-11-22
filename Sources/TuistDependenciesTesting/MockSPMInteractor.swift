import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockSPMInteractor: SPMInteracting {
    public init() {}
    
    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (path: AbsolutePath, method: InstallDependenciesMethod)?
    var invokedSaveParametersList = [(path: AbsolutePath, method: InstallDependenciesMethod)]()
    var stubbedSaveError: Error?
    
    public func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (path, method)
        invokedSaveParametersList.append((path, method))
        if let error = stubbedSaveError {
            throw error
        }
    }
}
