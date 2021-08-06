import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerController: SwiftPackageManagerControlling {
    public init() {}

    var invokedResolve = false
    var resolveStub: ((AbsolutePath, Bool) throws -> Void)?

    public func resolve(at path: AbsolutePath, printOutput: Bool) throws {
        invokedResolve = true
        try resolveStub?(path, printOutput)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, Bool) throws -> Void)?

    public func update(at path: AbsolutePath, printOutput: Bool) throws {
        invokedUpdate = true
        try updateStub?(path, printOutput)
    }

    var invokedSetToolsVersion = false
    var setToolsVersionStub: ((AbsolutePath, String?) throws -> Void)?

    public func setToolsVersion(at path: AbsolutePath, to version: String?) throws {
        invokedSetToolsVersion = true
        try setToolsVersionStub?(path, version)
    }

    var invokedLoadPackageInfo = false
    var loadPackageInfoStub: ((AbsolutePath) throws -> PackageInfo)?

    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        invokedLoadPackageInfo = true
        return try loadPackageInfoStub?(path) ?? .init(products: [], targets: [], platforms: [])
    }
}
