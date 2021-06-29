import ProjectDescription
import TSCBasic
import TuistGraph
import TuistGraphTesting

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: ((AbsolutePath, TuistGraph.CarthageDependencies, Set<TuistGraph.Platform>, Bool) throws -> TuistDependencies.DependenciesGraph)?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.CarthageDependencies,
        platforms: Set<TuistGraph.Platform>,
        shouldUpdate: Bool
    ) throws -> TuistDependencies.DependenciesGraph {
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
