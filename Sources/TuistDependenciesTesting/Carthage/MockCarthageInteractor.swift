import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting

@testable import TuistDependencies

public final class MockCarthageInteractor: CarthageInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: (
        (AbsolutePath, TuistGraph.CarthageDependencies, Set<TuistGraph.Platform>, Bool) throws -> TuistCore
            .DependenciesGraph
    )?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.CarthageDependencies,
        platforms: Set<TuistGraph.Platform>,
        shouldUpdate: Bool
    ) throws -> TuistCore.DependenciesGraph {
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
