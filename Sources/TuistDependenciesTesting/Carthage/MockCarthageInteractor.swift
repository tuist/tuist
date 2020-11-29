import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (dependenciesDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])?
    var invokedInstallParametersList = [(dependenciesDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])]()
    var stubbedInstallError: Error?

    public func install(dependenciesDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (dependenciesDirectoryPath, method, dependencies)
        invokedInstallParametersList.append((dependenciesDirectoryPath, method, dependencies))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
