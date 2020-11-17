import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}
    
    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (path: AbsolutePath, method: InstallDependenciesMethod, carthageDependencies: [CarthageDependency])?
    var invokedInstallParametersList = [(path: AbsolutePath, method: InstallDependenciesMethod, carthageDependencies: [CarthageDependency])]()
    var stubbedInstallError: Error?

    public func install(at path: AbsolutePath, method: InstallDependenciesMethod, carthageDependencies: [CarthageDependency]) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (path, method, carthageDependencies)
        invokedInstallParametersList.append((path, method, carthageDependencies))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
