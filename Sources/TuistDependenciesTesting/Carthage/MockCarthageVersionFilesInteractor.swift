import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageVersionFilesInteractor: CarthageVersionFilesInteracting {
    public init() {}
    
    var invokedCopyVersionFiles = false
    var invokedCopyVersionFilesCount = 0
    var invokedCopyVersionFilesParameters: (carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)?
    var invokedCopyVersionFilesParametersList = [(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)]()
    var stubbedCopyVersionFilesError: Error?
    
    public func copyVersionFiles(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws {
        invokedCopyVersionFiles = true
        invokedCopyVersionFilesCount += 1
        invokedCopyVersionFilesParameters = (carthageBuildDirectory, dependenciesDirectory)
        invokedCopyVersionFilesParametersList.append((carthageBuildDirectory, dependenciesDirectory))
        if let error = stubbedCopyVersionFilesError {
            throw error
        }
    }
}
