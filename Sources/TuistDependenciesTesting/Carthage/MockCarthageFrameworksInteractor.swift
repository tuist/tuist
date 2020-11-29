import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageFrameworksInteractor: CarthageFrameworksInteracting {
    public init() {}

    var invokedCopyFrameworks = false
    var invokedCopyFrameworksCount = 0
    var invokedCopyFrameworksParameters: (carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath)?
    var invokedCopyFrameworksParametersList = [(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath)]()
    var stubbedCopyFrameworksError: Error?

    public func copyFrameworks(carthageBuildDirectory: AbsolutePath, destinationDirectory: AbsolutePath) throws {
        invokedCopyFrameworks = true
        invokedCopyFrameworksCount += 1
        invokedCopyFrameworksParameters = (carthageBuildDirectory, destinationDirectory)
        invokedCopyFrameworksParametersList.append((carthageBuildDirectory, destinationDirectory))
        if let error = stubbedCopyFrameworksError {
            throw error
        }
    }
}
