import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageFrameworksInteractor: CarthageFrameworksInteracting {
    public init() {}
    
    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (path: AbsolutePath, temporaryDirectoryPath: AbsolutePath)?
    var invokedSaveParametersList = [(path: AbsolutePath, temporaryDirectoryPath: AbsolutePath)]()
    var stubbedSaveError: Error?
    
    public func save(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (path, temporaryDirectoryPath)
        invokedSaveParametersList.append((path, temporaryDirectoryPath))
        if let error = stubbedSaveError {
            throw error
        }
    }
}
