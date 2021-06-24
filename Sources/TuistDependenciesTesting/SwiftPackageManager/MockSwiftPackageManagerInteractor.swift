import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: ((AbsolutePath, SwiftPackageManagerDependencies, Set<Platform>, Bool, String?) throws -> DependenciesGraph)?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        platforms: Set<Platform>,
        shouldUpdate: Bool,
        swiftToolsVersion: String?
    ) throws -> DependenciesGraph {
        invokedInstall = true
        return try installStub?(dependenciesDirectory, dependencies, platforms, shouldUpdate, swiftToolsVersion) ?? .none
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
