import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedSave = false
    var invokedSaveCount = 0
    var invokedSaveParameters: (tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod)?
    var invokedSaveParametersList = [(tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod)]()
    var stubbedSaveError: Error?

    public func install(tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod) throws {
        invokedSave = true
        invokedSaveCount += 1
        invokedSaveParameters = (tuistDirectoryPath, method)
        invokedSaveParametersList.append((tuistDirectoryPath, method))
        if let error = stubbedSaveError {
            throw error
        }
    }
}
