import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageVersionFilesInteractor: CarthageVersionFilesInteracting {
    public init() {}
    
    var invokedSaveVersionFiles = false
    var invokedSaveVersionFilesCount = 0
    var invokedSaveVersionFilesParameters: (carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)?
    var invokedSaveVersionFilesParametersList = [(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)]()
    var stubbedSaveVersionFilesError: Error?
    
    public func saveVersionFiles(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws {
        invokedSaveVersionFiles = true
        invokedSaveVersionFilesCount += 1
        invokedSaveVersionFilesParameters = (carthageBuildDirectory, dependenciesDirectory)
        invokedSaveVersionFilesParametersList.append((carthageBuildDirectory, dependenciesDirectory))
        if let error = stubbedSaveVersionFilesError {
            throw error
        }
    }
    
    var invokedLoadVersionFiles = false
    var invokedLoadVersionFilesCount = 0
    var invokedLoadVersionFilesParameters: (carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)?
    var invokedLoadVersionFilesParametersList = [(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)]()
    var stubbedLoadVersionFilesError: Error?
    
    public func loadVersionFiles(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws {
        invokedLoadVersionFiles = true
        invokedLoadVersionFilesCount += 1
        invokedLoadVersionFilesParameters = (carthageBuildDirectory, dependenciesDirectory)
        invokedLoadVersionFilesParametersList.append((carthageBuildDirectory, dependenciesDirectory))
        if let error = stubbedLoadVersionFilesError {
            throw error
        }
    }
}
