import TSCBasic
import TSCUtility
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageController: CarthageControlling {
    public init() {}

    var invokedCanUseSystemCarthage = false
    var canUseSystemCarthageStub: (() -> Bool)?

    public func canUseSystemCarthage() -> Bool {
        invokedCanUseSystemCarthage = true
        return canUseSystemCarthageStub?() ?? false
    }

    var invokedCarthageVersion = false
    var carthageVersionStub: (() throws -> Version)?

    public func carthageVersion() throws -> Version {
        invokedCarthageVersion = true
        return try carthageVersionStub?() ?? Version(0, 0, 0)
    }

    var invokedIsXCFrameworksProductionSupported = false
    var isXCFrameworksProductionSupportedStub: (() -> Bool)?

    public func isXCFrameworksProductionSupported() throws -> Bool {
        invokedIsXCFrameworksProductionSupported = true
        return isXCFrameworksProductionSupportedStub?() ?? false
    }

    var invokedBootstrap = false
    var bootstrapStub: ((AbsolutePath, Set<TuistGraph.Platform>, Set<CarthageDependencies.Options>) throws -> Void)?

    public func bootstrap(
        at path: AbsolutePath,
        platforms: Set<TuistGraph.Platform>,
        options: Set<CarthageDependencies.Options>
    ) throws {
        invokedBootstrap = true
        try bootstrapStub?(path, platforms, options)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, Set<TuistGraph.Platform>, Set<CarthageDependencies.Options>) throws -> Void)?

    public func update(
        at path: AbsolutePath,
        platforms: Set<TuistGraph.Platform>,
        options: Set<CarthageDependencies.Options>
    ) throws {
        invokedUpdate = true
        try updateStub?(path, platforms, options)
    }
}
