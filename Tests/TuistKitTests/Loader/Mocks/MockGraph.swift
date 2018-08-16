import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockGraph: Graphing {
    let name: String
    let entryPath: AbsolutePath
    let entryNodes: [GraphNode]
    let cache: GraphLoaderCaching
    let projects: [Project]
    let precompiledNodes: [PrecompiledNode]
    var linkableDependenciesCallStub: ((AbsolutePath, String) throws -> [DependencyReference])?
    var librariesPublicHeadersFoldersStub: ((AbsolutePath, String) -> [AbsolutePath])?
    var embeddableFrameworksStub: ((AbsolutePath, String, Systeming) throws -> [DependencyReference])?
    var dependenciesWithNameStub: ((AbsolutePath, String) -> Set<GraphNode>)?
    var dependenciesStub: ((AbsolutePath) -> Set<GraphNode>)?
    var targetDependenciesStub: ((AbsolutePath, String) -> [String])?

    init(name: String = "Test",
         entryPath: AbsolutePath,
         cache: GraphLoaderCaching = GraphLoaderCache(),
         projects: [Project] = [],
         entryNodes: [GraphNode] = [],
         precompiledNodes: [PrecompiledNode] = []) {
        self.name = name
        self.entryPath = entryPath
        self.projects = projects
        self.entryNodes = entryNodes
        self.precompiledNodes = precompiledNodes
        self.cache = cache
    }

    func linkableDependencies(path: AbsolutePath, name: String) throws -> [DependencyReference] {
        return try linkableDependenciesCallStub?(path, name) ?? []
    }

    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        return librariesPublicHeadersFoldersStub?(path, name) ?? []
    }

    func embeddableFrameworks(path: AbsolutePath, name: String, system: Systeming) throws -> [DependencyReference] {
        return try embeddableFrameworksStub?(path, name, system) ?? []
    }

    func dependencies(path: AbsolutePath, name: String) -> Set<GraphNode> {
        return dependenciesWithNameStub?(path, name) ?? Set()
    }

    func dependencies(path: AbsolutePath) -> Set<GraphNode> {
        return dependenciesStub?(path) ?? Set()
    }

    func targetDependencies(path: AbsolutePath, name: String) -> [String] {
        return targetDependenciesStub?(path, name) ?? []
    }
}
