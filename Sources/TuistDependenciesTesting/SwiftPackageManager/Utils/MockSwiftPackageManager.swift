import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManager: SwiftPackageManaging {
    public init() {}

    var invokedResolve = false
    var invokedResolveCount = 0
    var invokedResolveParameters: AbsolutePath?
    var invokedResolveParametersList = [AbsolutePath]()
    var resolveStub: ((AbsolutePath) throws -> Void)?

    public func resolve(at path: AbsolutePath) throws {
        invokedResolve = true
        invokedResolveCount += 1
        invokedResolveParameters = path
        invokedResolveParametersList.append(path)
        try resolveStub?(path)
    }

    var invokedUpdate = false
    var invokedUpdateCount = 0
    var invokedUpdateParameters: AbsolutePath?
    var invokedUpdateParametersList = [AbsolutePath]()
    var updateStub: ((AbsolutePath) throws -> Void)?

    public func update(at path: AbsolutePath) throws {
        invokedUpdate = true
        invokedUpdateCount += 1
        invokedUpdateParameters = path
        invokedUpdateParametersList.append(path)
        try updateStub?(path)
    }
}
