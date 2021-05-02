import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthage: Carthaging {
    public init() {}

    var invokedBootstrap = false
    var bootstrapStub: ((AbsolutePath, Set<Platform>, Set<CarthageDependencies.Options>) throws -> Void)?

    public func bootstrap(
        at path: AbsolutePath,
        platforms: Set<Platform>,
        options: Set<CarthageDependencies.Options>
    ) throws {
        invokedBootstrap = true
        try bootstrapStub?(path, platforms, options)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, Set<Platform>, Set<CarthageDependencies.Options>) throws -> Void)?

    public func update(
        at path: AbsolutePath,
        platforms: Set<Platform>,
        options: Set<CarthageDependencies.Options>
    ) throws {
        invokedUpdate = true
        try updateStub?(path, platforms, options)
    }
}
