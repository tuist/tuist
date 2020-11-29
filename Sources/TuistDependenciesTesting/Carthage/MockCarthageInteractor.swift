import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: (tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])?
    var invokedInstallParametersList = [(tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency])]()
    var stubbedInstallError: Error?

    public func install(tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = (tuistDirectoryPath, method, dependencies)
        invokedInstallParametersList.append((tuistDirectoryPath, method, dependencies))
        if let error = stubbedInstallError {
            throw error
        }
    }
}
