import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: ((AbsolutePath, CarthageDependencies, Set<Platform>, Bool) throws -> Void)?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: CarthageDependencies,
        platforms: Set<Platform>,
        shouldUpdate: Bool
    ) throws {
        invokedInstall = true
        try installStub?(dependenciesDirectory, dependencies, platforms, shouldUpdate)
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
