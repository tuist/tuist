import Foundation
import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockDependenciesGraphController: DependenciesGraphControlling {
    public init() {}

    var invokedSave = false
    var saveStub: ((TuistGraph.DependenciesGraph, AbsolutePath) throws -> Void)?

    public func save(_ dependenciesGraph: TuistGraph.DependenciesGraph, to path: AbsolutePath) throws {
        invokedSave = true
        try saveStub?(dependenciesGraph, path)
    }

    var invokedLoad = false
    var loadStub: ((AbsolutePath) throws -> TuistGraph.DependenciesGraph)?

    public func load(at path: AbsolutePath) throws -> TuistGraph.DependenciesGraph {
        invokedLoad = true
        return try loadStub?(path) ?? .test()
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(at path: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(path)
    }
}
