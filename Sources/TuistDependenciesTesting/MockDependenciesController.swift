import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}

    public var invokedFetch = false
    public var fetchStub: ((AbsolutePath, TuistGraph.Dependencies, TSCUtility.Version?) throws -> TuistCore.DependenciesGraph)?

    public func fetch(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        invokedFetch = true
        return try fetchStub?(path, dependencies, swiftVersion) ?? .none
    }

    public var invokedUpdate = false
    public var updateStub: ((AbsolutePath, TuistGraph.Dependencies, TSCUtility.Version?) throws -> TuistCore.DependenciesGraph)?

    public func update(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        invokedUpdate = true
        return try updateStub?(path, dependencies, swiftVersion) ?? .none
    }

    public var invokedSave = false
    public var saveStub: ((TuistGraph.DependenciesGraph, AbsolutePath) throws -> Void)?

    public func save(dependenciesGraph: TuistGraph.DependenciesGraph, to path: AbsolutePath) throws {
        invokedSave = true
        try saveStub?(dependenciesGraph, path)
    }
}
