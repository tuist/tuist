import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// It defines the interface to mutate a graph using information from the cache.
protocol CacheGraphMutating {
    /// Given a graph an a dictionary whose keys are targets of the graph, and the values are paths
    /// to the .xcframeworks in the cache, it mutates the graph to link the enry nodes against the .xcframeworks instead.
    /// - Parameters:
    ///   - graph: Dependency graph.
    ///   - precompiledFrameworks: Dictionary that maps targets with the paths to their cached `.framework`s or `.xcframework`s.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(graph: Graph, precompiledFrameworks: [GraphTarget: AbsolutePath], sources: Set<String>) throws -> Graph
}

class CacheGraphMutator: CacheGraphMutating {
    struct VisitedPrecompiledFramework {
        let path: AbsolutePath?
    }

    // MARK: - Attributes

    /// Utility to parse an .xcframework from the filesystem and load it into memory.
    private let xcframeworkLoader: XCFrameworkLoading

    /// Utility to parse a .framework from the filesystem and load it into memory.
    private let frameworkLoader: FrameworkLoading

    /// Initializes the graph mapper with its attributes.
    /// - Parameter xcframeworkLoader: Utility to parse an .xcframework from the filesystem and load it into memory.
    init(frameworkLoader: FrameworkLoading = FrameworkLoader(),
         xcframeworkLoader: XCFrameworkLoading = XCFrameworkLoader())
    {
        self.frameworkLoader = frameworkLoader
        self.xcframeworkLoader = xcframeworkLoader
    }

    // MARK: - CacheGraphMapping

    /// Given a graph an a dictionary whose keys are targets of the graph, and the values are paths
    /// to the .xcframeworks in the cache, it mutates the graph to link the enry nodes against the .xcframeworks instead.
    /// - Parameters:
    ///   - graph: Dependency graph.
    ///   - precompiledFrameworks: Dictionary that maps targets with the paths to their cached `.framework`s or `.xcframework`s.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(
        graph: Graph,
        precompiledFrameworks: [GraphTarget: AbsolutePath],
        sources: Set<String>
    ) throws -> Graph {
        var graph = graph
        let graphTraverser = GraphTraverser(graph: graph)
        var visitedPrecompiledFrameworkPaths: [GraphTarget: VisitedPrecompiledFramework?] = [:]
        var loadedPrecompiledDependencies: [AbsolutePath: GraphDependency] = [:]
        let userSpecifiedSourceTargets = graphTraverser.allTargets().filter { sources.contains($0.target.name) }
        let userSpecifiedSourceTestTargets = userSpecifiedSourceTargets.flatMap {
            graphTraverser.testTargetsDependingOn(path: $0.path, name: $0.target.name)
        }
        var sourceTargets: Set<GraphTarget> = Set(userSpecifiedSourceTargets)

        /// New graph dependencies
        var graphDependencies: [GraphDependency: Set<GraphDependency>] = [:]
        try (userSpecifiedSourceTargets + userSpecifiedSourceTestTargets)
            .forEach {
                try visit(
                    target: $0,
                    graph: graph,
                    graphDependencies: &graphDependencies,
                    precompiledFrameworks: precompiledFrameworks,
                    sources: sources,
                    sourceTargets: &sourceTargets,
                    visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                    loadedPrecompiledNodes: &loadedPrecompiledDependencies
                )
            }
        graph.dependencies = graphDependencies

        // We mark them to be pruned during the tree-shaking
        graphTraverser.allTargets().forEach { graphTarget in
            if !sourceTargets.contains(graphTarget) {
                var target = graphTarget.target
                target.prune = true
                graph.targets[graphTarget.path]?[target.name] = target
            }
        }

        return graph
    }

    fileprivate func visit(
        target: GraphTarget,
        graph: Graph,
        graphDependencies: inout [GraphDependency: Set<GraphDependency>],
        precompiledFrameworks: [GraphTarget: AbsolutePath],
        sources: Set<String>,
        sourceTargets: inout Set<GraphTarget>,
        visitedPrecompiledFrameworkPaths: inout [GraphTarget: VisitedPrecompiledFramework?],
        loadedPrecompiledNodes: inout [AbsolutePath: GraphDependency]
    ) throws {
        sourceTargets.formUnion([target])
        let targetDependency: GraphDependency = .target(name: target.target.name, path: target.path)
        graphDependencies[
            targetDependency
        ] = try mapDependencies(
            graph.dependencies[targetDependency, default: Set()],
            graph: graph,
            graphDependencies: &graphDependencies,
            precompiledFrameworks: precompiledFrameworks,
            sources: sources,
            sourceTargets: &sourceTargets,
            visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
            loadedPrecompiledFrameworks: &loadedPrecompiledNodes
        )
    }

    // swiftlint:disable:next function_body_length
    fileprivate func mapDependencies(
        _ dependencies: Set<GraphDependency>,
        graph: Graph,
        graphDependencies: inout [GraphDependency: Set<GraphDependency>],
        precompiledFrameworks: [GraphTarget: AbsolutePath],
        sources: Set<String>,
        sourceTargets: inout Set<GraphTarget>,
        visitedPrecompiledFrameworkPaths: inout [GraphTarget: VisitedPrecompiledFramework?],
        loadedPrecompiledFrameworks: inout [AbsolutePath: GraphDependency]
    ) throws -> Set<GraphDependency> {
        var newDependencies: Set<GraphDependency> = Set()
        try dependencies.forEach { dependency in
            let graphTraverser = GraphTraverser(graph: graph)
            let targetDependency: GraphTarget
            switch dependency {
            case let .target(name: name, path: path):
                guard
                    let target = graphTraverser.target(path: path, name: name)
                else { return }
                targetDependency = target
            // If the dependency is not a target node we keep it.
            default:
                newDependencies.insert(dependency)
                return
            }

            // Transitive bundles
            // get all the transitive bundles
            // declare them as direct dependencies.

            // If the target cannot be replaced with its associated .(xc)framework we return
            guard
                !sources.contains(targetDependency.target.name),
                let precompiledFrameworkPath = precompiledFrameworkPath(
                    target: targetDependency,
                    graphTraverser: graphTraverser,
                    precompiledFrameworks: precompiledFrameworks,
                    visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths
                )
            else {
                sourceTargets.formUnion([targetDependency])
                graphDependencies[dependency] = try mapDependencies(
                    graphTraverser.dependencies[dependency] ?? Set(),
                    graph: graph,
                    graphDependencies: &graphDependencies,
                    precompiledFrameworks: precompiledFrameworks,
                    sources: sources,
                    sourceTargets: &sourceTargets,
                    visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                    loadedPrecompiledFrameworks: &loadedPrecompiledFrameworks
                )
                newDependencies.insert(dependency)
                return
            }

            // We load the .framework (or fallback on .xcframework)
            let precompiledFramework: GraphDependency = try loadPrecompiledFramework(
                path: precompiledFrameworkPath,
                loadedPrecompiledFrameworks: &loadedPrecompiledFrameworks
            )

            try mapDependencies(
                graphTraverser.dependencies[dependency] ?? Set(),
                graph: graph,
                graphDependencies: &graphDependencies,
                precompiledFrameworks: precompiledFrameworks,
                sources: sources,
                sourceTargets: &sourceTargets,
                visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                loadedPrecompiledFrameworks: &loadedPrecompiledFrameworks
            ).forEach { dependency in
                switch dependency {
                case .framework, .xcframework:
                    var precompiledDependencies = graphDependencies[precompiledFramework, default: Set()]
                    precompiledDependencies.insert(dependency)
                    graphDependencies[precompiledFramework] = precompiledDependencies
                default:
                    // Static dependencies fall into this case.
                    // Those are now part of the precompiled (xc)framework and therefore we don't have to link against them.
                    break
                }
            }
            newDependencies.insert(precompiledFramework)
        }
        return newDependencies
    }

    fileprivate func loadPrecompiledFramework(
        path: AbsolutePath,
        loadedPrecompiledFrameworks: inout [AbsolutePath: GraphDependency]
    ) throws -> GraphDependency {
        if let cachedFramework = loadedPrecompiledFrameworks[path] {
            return cachedFramework
        } else if let framework: GraphDependency = try? frameworkLoader.load(path: path) {
            loadedPrecompiledFrameworks[path] = framework
            return framework
        } else {
            let xcframework: GraphDependency = try xcframeworkLoader.load(path: path)
            loadedPrecompiledFrameworks[path] = xcframework
            return xcframework
        }
    }

    fileprivate func precompiledFrameworkPath(
        target: GraphTarget,
        graphTraverser: GraphTraversing,
        precompiledFrameworks: [GraphTarget: AbsolutePath],
        visitedPrecompiledFrameworkPaths: inout [GraphTarget: VisitedPrecompiledFramework?]
    ) -> AbsolutePath? {
        // Already visited
        if let visited = visitedPrecompiledFrameworkPaths[target] { return visited?.path }

        // The target doesn't have a cached .(xc)framework
        if precompiledFrameworks[target] == nil {
            visitedPrecompiledFrameworkPaths[target] = VisitedPrecompiledFramework(path: nil)
            return nil
        }
        // The target can be replaced
        else if
            let path = precompiledFrameworks[target],
            graphTraverser.directTargetDependencies(path: target.path, name: target.target.name).allSatisfy({
                precompiledFrameworkPath(
                    target: $0,
                    graphTraverser: graphTraverser,
                    precompiledFrameworks: precompiledFrameworks,
                    visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths
                ) != nil
            })
        {
            visitedPrecompiledFrameworkPaths[target] = VisitedPrecompiledFramework(path: path)
            return path
        } else {
            visitedPrecompiledFrameworkPaths[target] = VisitedPrecompiledFramework(path: nil)
            return nil
        }
    }
}
