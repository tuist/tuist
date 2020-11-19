import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}
    
    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (path: AbsolutePath, method: InstallDependenciesMethod, dependencies: Dependencies)?
    var invokedInstallParametersList = [(path: AbsolutePath, method: InstallDependenciesMethod, dependencies: Dependencies)]()
    var stubbedInstallError: Error?

    public func install(at path: AbsolutePath, method: InstallDependenciesMethod, dependencies: Dependencies) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (path, method, dependencies)
        invokedInstallParametersList.append((path, method, dependencies))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
