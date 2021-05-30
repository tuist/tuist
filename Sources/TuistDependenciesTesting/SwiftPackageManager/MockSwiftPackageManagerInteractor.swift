import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((AbsolutePath, SwiftPackageManagerDependencies, String?) throws -> Void)?

    public func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        swiftToolsVersion: String?
    ) throws {
        invokedFetch = true
        try fetchStub?(dependenciesDirectory, dependencies, swiftToolsVersion)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, SwiftPackageManagerDependencies, String?) throws -> Void)?

    public func update(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        swiftToolsVersion: String?
    ) throws {
        invokedUpdate = true
        try updateStub?(dependenciesDirectory, dependencies, swiftToolsVersion)
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
