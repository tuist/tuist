import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerController: SwiftPackageManagerControlling {
    public init() {}

    var invokedResolve = false
    var resolveStub: ((AbsolutePath) throws -> Void)?

    public func resolve(at path: AbsolutePath) throws {
        invokedResolve = true
        try resolveStub?(path)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath) throws -> Void)?

    public func update(at path: AbsolutePath) throws {
        invokedUpdate = true
        try updateStub?(path)
    }

    var invokedSetToolsVersion = false
    var setToolsVersionStub: ((AbsolutePath, String?) throws -> Void)?

    public func setToolsVersion(at path: AbsolutePath, to version: String?) throws {
        invokedSetToolsVersion = true
        try setToolsVersionStub?(path, version)
    }
}
