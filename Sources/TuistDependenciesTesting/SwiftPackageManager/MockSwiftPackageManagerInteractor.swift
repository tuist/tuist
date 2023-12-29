import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: (
        (
            AbsolutePath,
            TuistGraph.Dependencies,
            Bool,
            TSCUtility.Version?
        ) throws -> TuistCore.DependenciesGraph
    )?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        shouldUpdate: Bool,
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        invokedInstall = true
        return try installStub?(dependenciesDirectory, dependencies, shouldUpdate, swiftToolsVersion) ?? .none
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath, dependencies: TuistGraph.Dependencies) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
