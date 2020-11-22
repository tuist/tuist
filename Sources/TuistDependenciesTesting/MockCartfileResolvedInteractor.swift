import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCartfileResolvedInteractor: CartfileResolvedInteracting {
    public init() {}
    
    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (path: AbsolutePath, temporaryDirectoryPath: AbsolutePath)?
    var invokedSaveParametersList = [(path: AbsolutePath, temporaryDirectoryPath: AbsolutePath)]()
    var stubbedSaveError: Error?
    
    public func save(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (path,temporaryDirectoryPath)
        invokedSaveParametersList.append((path, temporaryDirectoryPath))
        if let error = stubbedSaveError {
            throw error
        }
    }
    
    var invokedLoadIfExist = false
    var invokedLoadIfExistCount = 0
    var invokedLoadIfExistParameters: (path: AbsolutePath, temporaryDirectoryPath: AbsolutePath)?
    var invokedLoadIfExistParametersList = [(path: AbsolutePath, temporaryDirectoryPath: AbsolutePath)]()
    var stubbedLoadIfExistError: Error?
    
    public func loadIfExist(from path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        invokedLoadIfExist = true
        invokedLoadIfExistCount += 1
        invokedLoadIfExistParameters = (path, temporaryDirectoryPath)
        invokedLoadIfExistParametersList.append((path, temporaryDirectoryPath))
        if let error = stubbedLoadIfExistError {
            throw error
        }
    }
}
