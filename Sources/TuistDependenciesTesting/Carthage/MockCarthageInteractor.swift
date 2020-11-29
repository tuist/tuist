import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])?
    var invokedInstallParametersList = [(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])]()
    var stubbedInstallError: Error?

    public func install(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (dependenciesDirectory, method, dependencies)
        invokedInstallParametersList.append((dependenciesDirectory, method, dependencies))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
