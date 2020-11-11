import TSCBasic
@testable import TuistDependencies

#warning("TODO: Replace with TuistCore when models will be ready.")
import ProjectDescription

public final class MockDependenciesController: DependenciesControlling {
    public init() {}
    
    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (path: AbsolutePath, method: InstallDependenciesMethod, dependencies: [ProjectDescription.Dependency])?
    var invokedInstallParametersList = [(path: AbsolutePath, method: InstallDependenciesMethod, dependencies: [ProjectDescription.Dependency])]()
    var stubbedInstallError: Error?

    public func install(at path: AbsolutePath, method: InstallDependenciesMethod, dependencies: [ProjectDescription.Dependency]) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (path, method, dependencies)
        invokedInstallParametersList.append((path, method, dependencies))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
