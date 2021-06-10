import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: ((AbsolutePath, SwiftPackageManagerDependencies, Bool, String?) throws -> DependenciesGraph)?

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        shouldUpdate: Bool,
        swiftToolsVersion: String?
    ) throws -> DependenciesGraph {
        invokedInstall = true
        return try installStub?(dependenciesDirectory, dependencies, shouldUpdate, swiftToolsVersion) ?? .init(thirdPartyDependencies: [:])
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
