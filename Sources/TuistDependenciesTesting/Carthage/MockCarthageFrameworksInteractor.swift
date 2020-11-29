import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageFrameworksInteractor: CarthageFrameworksInteracting {
    public init() {}

    var invokedCopyFrameworks = false
    var invokedCopyFrameworksCount = 0
    var invokedCopyFrameworksParameters: (carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)?
    var invokedCopyFrameworksParametersList = [(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath)]()
    var stubbedCopyFrameworksError: Error?

    public func copyFrameworks(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws {
        invokedCopyFrameworks = true
        invokedCopyFrameworksCount += 1
        invokedCopyFrameworksParameters = (carthageBuildDirectory, dependenciesDirectory)
        invokedCopyFrameworksParametersList.append((carthageBuildDirectory, dependenciesDirectory))
        if let error = stubbedCopyFrameworksError {
            throw error
        }
    }
}
