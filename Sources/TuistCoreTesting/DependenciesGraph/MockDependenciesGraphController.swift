import Foundation
import TSCBasic
import TuistGraph

@testable import TuistCore

public final class MockDependenciesGraphController: DependenciesGraphControlling {
    public init() {}

    var invokedSave = false
    var saveStub: ((DependenciesGraph, AbsolutePath) throws -> Void)?

    public func save(_ dependenciesGraph: DependenciesGraph, at path: AbsolutePath) throws {
        invokedSave = true
        try saveStub?(dependenciesGraph, path)
    }

    var invokedLoad = false
    var loadStub: ((AbsolutePath) throws -> DependenciesGraph)?

    public func load(at path: AbsolutePath) throws -> DependenciesGraph {
        invokedLoad = true
        return try loadStub?(path) ?? .test()
    }
}
