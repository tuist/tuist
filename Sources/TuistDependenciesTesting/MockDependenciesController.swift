import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((AbsolutePath, TuistGraph.Dependencies, TSCUtility.Version?) throws -> TuistCore.DependenciesGraph)?

    public func fetch(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        invokedFetch = true
        return try fetchStub?(path, dependencies, swiftVersion) ?? .none
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath, TuistGraph.Dependencies, TSCUtility.Version?) throws -> TuistCore.DependenciesGraph)?

    public func update(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        invokedUpdate = true
        return try updateStub?(path, dependencies, swiftVersion) ?? .none
    }

    var invokedSave = false
    var saveStub: ((TuistGraph.DependenciesGraph, AbsolutePath) throws -> Void)?

    public func save(dependenciesGraph: TuistGraph.DependenciesGraph, to path: AbsolutePath) throws {
        invokedSave = true
        try saveStub?(dependenciesGraph, path)
    }
}
