import TSCBasic
@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}
    
    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (path: AbsolutePath, method: InstallDependenciesMethod)?
    var invokedInstallParametersList = [(path: AbsolutePath, method: InstallDependenciesMethod)]()
    var stubbedInstallError: Error?

    public func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (path, method)
        invokedInstallParametersList.append((path, method))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
