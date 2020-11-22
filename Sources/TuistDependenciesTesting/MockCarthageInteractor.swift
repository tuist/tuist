import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}
    
    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (path: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])?
    var invokedSaveParametersList = [(path: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])]()
    var stubbedSaveError: Error?
    
    public func install(at path: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (path, method, dependencies)
        invokedSaveParametersList.append((path, method, dependencies))
        if let error = stubbedSaveError {
            throw error
        }
    }
}
