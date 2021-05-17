import TSCBasic
import TuistGraph
import TuistGraphTesting

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: ((AbsolutePath, CarthageDependencies, Set<Platform>, Bool) throws -> DependenciesGraph)?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: CarthageDependencies,
        platforms: Set<Platform>,
        shouldUpdate: Bool
    ) throws -> DependenciesGraph {
        invokedInstall = true
        return try installStub?(dependenciesDirectory, dependencies, platforms, shouldUpdate) ?? .test()
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
