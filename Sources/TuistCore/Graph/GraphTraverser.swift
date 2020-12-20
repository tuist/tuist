import Foundation
import TSCBasic

public final class GraphTraverser {
    private let graph: Graph
    public var name: String { graph.name }
    public var hasPackages: Bool { !graph.packages.isEmpty }
    public var path: AbsolutePath { graph.entryPath }
    public var workspace: Workspace { graph.workspace }
    public let projects: [AbsolutePath: Project]
    public let targets: [AbsolutePath: [String: Target]]

    public init(graph: Graph) {
        self.graph = graph
        projects = Dictionary(uniqueKeysWithValues: graph.projects.map { ($0.path, $0) })
        targets = graph.targets.mapValues { (targets: [TargetNode]) -> [String: Target] in
            Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0.target) })
        }
    }

    public func rootTargets() -> Set<ValueGraphTarget> {
        Set(graph.entryNodes.compactMap { $0 as? TargetNode }
            .map { ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project) })
    }

    public func precompiledFrameworksPaths() -> Set<AbsolutePath> {
        Set(graph.precompiled.compactMap { $0 as? FrameworkNode }.map(\.path))
    }

    public func targets(product: Product) -> Set<ValueGraphTarget> {
        Set(graph.targets.flatMap(\.value).compactMap { (target: TargetNode) -> ValueGraphTarget? in
            guard target.target.product == product else { return nil }
            return ValueGraphTarget(path: target.path, target: target.target, project: target.project)
        })
    }

    public func target(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        graph.target(path: path, name: name).map {
            ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project)
        }
    }

    public func targets(at path: AbsolutePath) -> Set<ValueGraphTarget> {
        Set(graph.targets(at: path).map {
            ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project)
        })
    }

    public func directTargetDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        Set(graph.targetDependencies(path: path, name: name).map {
            ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project)
        })
    }

    public func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        Set(graph.appExtensionDependencies(path: path, name: name).map {
            ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project)
        })
    }

    public func resourceBundleDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        Set(graph.resourceBundleDependencies(path: path, name: name).map {
            ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project)
        })
    }

    public func testTargetsDependingOn(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        Set(graph.testTargetsDependingOn(path: path, name: name).map {
            ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project)
        })
    }

    public func directStaticDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        Set(graph.staticDependencies(path: path, name: name))
    }

    public func appClipDependencies(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        graph.appClipDependencies(path: path, name: name).map { ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project) }
    }

    public func embeddableFrameworks(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        Set(graph.embeddableFrameworks(path: path, name: name))
    }

    public func linkableDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference> {
        try Set(graph.linkableDependencies(path: path, name: name))
    }

    public func copyProductDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        guard let target = graph.target(path: path, name: name) else { return Set() }
        return Set(graph.copyProductDependencies(path: path, target: target.target))
    }

    public func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        Set(graph.librariesPublicHeadersFolders(path: path, name: name))
    }

    public func librariesSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        Set(graph.librariesSearchPaths(path: path, name: name))
    }

    public func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        Set(graph.librariesSwiftIncludePaths(path: path, name: name))
    }

    public func runPathSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        Set(graph.runPathSearchPaths(path: path, name: name))
    }

    public func hostTargetFor(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        graph.hostTargetNodeFor(path: path, name: name)
            .map { ValueGraphTarget(path: $0.path, target: $0.target, project: $0.project) }
    }

    public func allProjectDependencies(path: AbsolutePath) throws -> Set<GraphDependencyReference> {
        guard let project = projects[path] else { return Set() }
        return try Set(graph.allDependencyReferences(for: project))
    }
}
