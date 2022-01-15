import Foundation
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
    ///   - precompiledArtifacts: Dictionary that maps targets with the paths to their cached `.framework`s, `.xcframework`s or `.bundle`s.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(graph: Graph, precompiledArtifacts: [GraphTarget: AbsolutePath], sources: Set<String>) throws -> Graph
}

// swiftlint:disable:next type_body_length
class CacheGraphMutator: CacheGraphMutating {
    struct VisitedArtifact {
        let path: AbsolutePath?
    }

    // MARK: - Attributes

    /// Utility to parse an .xcframework from the filesystem and load it into memory.
    private let xcframeworkLoader: XCFrameworkLoading

    /// Utility to parse a .framework from the filesystem and load it into memory.
    private let frameworkLoader: FrameworkLoading

    /// Utility to parse a .bundle from the filesystem and load it into memory.
    private let bundleLoader: BundleLoading

    /// Initializes the graph mapper with its attributes.
    /// - Parameter xcframeworkLoader: Utility to parse an .xcframework from the filesystem and load it into memory.
    init(frameworkLoader: FrameworkLoading = FrameworkLoader(),
         xcframeworkLoader: XCFrameworkLoading = XCFrameworkLoader(),
         bundleLoader: BundleLoading = BundleLoader())
    {
        self.frameworkLoader = frameworkLoader
        self.xcframeworkLoader = xcframeworkLoader
        self.bundleLoader = bundleLoader
    }

    // MARK: - CacheGraphMapping

    /// Given a graph an a dictionary whose keys are targets of the graph, and the values are paths
    /// to the .xcframeworks in the cache, it mutates the graph to link the enry nodes against the .xcframeworks instead.
    /// - Parameters:
    ///   - graph: Dependency graph.
    ///   - precompiledArtifacts: Dictionary that maps targets with the paths to their cached `.framework`s, `.xcframework`s or `.bundle`s.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(
        graph: Graph,
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        sources: Set<String>
    ) throws -> Graph {
        var graph = graph
        let graphTraverser = GraphTraverser(graph: graph)
        var visitedPrecompiledArtifactPaths: [GraphTarget: VisitedArtifact?] = [:]
        var loadedPrecompiledDependencies: [AbsolutePath: GraphDependency] = [:]
        let userSpecifiedSourceTargets = graphTraverser.allTargets().filter { sources.contains($0.target.name) }
        var sourceTargets = Set(userSpecifiedSourceTargets)

        /// New graph dependencies
        var graphDependencies: [GraphDependency: Set<GraphDependency>] = [:]
        try userSpecifiedSourceTargets.forEach {
            try visit(
                target: $0,
                graph: graph,
                graphDependencies: &graphDependencies,
                precompiledArtifacts: precompiledArtifacts,
                sources: sources,
                sourceTargets: &sourceTargets,
                visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths,
                loadedPrecompiledNodes: &loadedPrecompiledDependencies
            )
        }

        mapPrebuiltFrameworks(
            graphDependencies: &graphDependencies,
            graph: graph
        )

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
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        sources: Set<String>,
        sourceTargets: inout Set<GraphTarget>,
        visitedPrecompiledArtifactPaths: inout [GraphTarget: VisitedArtifact?],
        loadedPrecompiledNodes: inout [AbsolutePath: GraphDependency]
    ) throws {
        sourceTargets.formUnion([target])
        let targetDependency: GraphDependency = .target(name: target.target.name, path: target.path)
        graphDependencies[targetDependency] = try mapDependencies(
            graph.dependencies[targetDependency, default: Set()],
            graph: graph,
            graphDependencies: &graphDependencies,
            precompiledArtifacts: precompiledArtifacts,
            sources: sources,
            sourceTargets: &sourceTargets,
            visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths,
            loadedPrecompiledArtifacts: &loadedPrecompiledNodes
        )
    }

    // swiftlint:disable:next function_body_length
    fileprivate func mapDependencies(
        _ dependencies: Set<GraphDependency>,
        graph: Graph,
        graphDependencies: inout [GraphDependency: Set<GraphDependency>],
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        sources: Set<String>,
        sourceTargets: inout Set<GraphTarget>,
        visitedPrecompiledArtifactPaths: inout [GraphTarget: VisitedArtifact?],
        loadedPrecompiledArtifacts: inout [AbsolutePath: GraphDependency]
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

            // If the target cannot be replaced with its associated .(xc)framework or .bundle we return
            guard
                !sources.contains(targetDependency.target.name),
                let precompiledArtifactPath = precompiledArtifactPath(
                    target: targetDependency,
                    graphTraverser: graphTraverser,
                    precompiledArtifacts: precompiledArtifacts,
                    visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths
                )
            else {
                sourceTargets.formUnion([targetDependency])

                visitBundleTargets(
                    for: dependency,
                    graphTraverser: graphTraverser,
                    visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths
                )

                graphDependencies[dependency] = try mapDependencies(
                    graphTraverser.dependencies[dependency] ?? Set(),
                    graph: graph,
                    graphDependencies: &graphDependencies,
                    precompiledArtifacts: precompiledArtifacts,
                    sources: sources,
                    sourceTargets: &sourceTargets,
                    visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths,
                    loadedPrecompiledArtifacts: &loadedPrecompiledArtifacts
                )
                newDependencies.insert(dependency)
                return
            }

            // We load the .framework or .xcframework or .bundle
            let precompiledArtifact: GraphDependency = try loadPrecompiledArtifact(
                path: precompiledArtifactPath,
                loadedPrecompiledArtifacts: &loadedPrecompiledArtifacts
            )

            try mapDependencies(
                graphTraverser.dependencies[dependency] ?? Set(),
                graph: graph,
                graphDependencies: &graphDependencies,
                precompiledArtifacts: precompiledArtifacts,
                sources: sources,
                sourceTargets: &sourceTargets,
                visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths,
                loadedPrecompiledArtifacts: &loadedPrecompiledArtifacts
            ).forEach { dependency in
                switch dependency {
                case .framework, .xcframework, .bundle, .sdk:
                    var precompiledDependencies = graphDependencies[precompiledArtifact, default: Set()]
                    precompiledDependencies.insert(dependency)
                    graphDependencies[precompiledArtifact] = precompiledDependencies
                case .library, .packageProduct, .target:
                    // Static dependencies fall into this case.
                    // Those are now part of the precompiled (xc)framework and therefore we don't have to link against them.
                    break
                }
            }
            newDependencies.insert(precompiledArtifact)
        }
        return newDependencies
    }

    fileprivate func loadPrecompiledArtifact(
        path: AbsolutePath,
        loadedPrecompiledArtifacts: inout [AbsolutePath: GraphDependency]
    ) throws -> GraphDependency {
        if let cachedArtifact = loadedPrecompiledArtifacts[path] {
            return cachedArtifact
        } else if let framework: GraphDependency = try? frameworkLoader.load(path: path) {
            loadedPrecompiledArtifacts[path] = framework
            return framework
        } else if let xcframework: GraphDependency = try? xcframeworkLoader.load(path: path) {
            loadedPrecompiledArtifacts[path] = xcframework
            return xcframework
        } else {
            let bundle = try bundleLoader.load(path: path)
            loadedPrecompiledArtifacts[path] = bundle
            return bundle
        }
    }

    fileprivate func precompiledArtifactPath(
        target: GraphTarget,
        graphTraverser: GraphTraversing,
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        visitedPrecompiledArtifactPaths: inout [GraphTarget: VisitedArtifact?]
    ) -> AbsolutePath? {
        // Already visited
        if let visited = visitedPrecompiledArtifactPaths[target] { return visited?.path }

        // The target doesn't have a cached .(xc)framework
        if precompiledArtifacts[target] == nil {
            visitedPrecompiledArtifactPaths[target] = VisitedArtifact(path: nil)
            return nil
        }
        // The target can be replaced
        else if
            let path = precompiledArtifacts[target],
            graphTraverser.directTargetDependencies(path: target.path, name: target.target.name).allSatisfy({
                precompiledArtifactPath(
                    target: $0,
                    graphTraverser: graphTraverser,
                    precompiledArtifacts: precompiledArtifacts,
                    visitedPrecompiledArtifactPaths: &visitedPrecompiledArtifactPaths
                ) != nil
            })
        {
            visitedPrecompiledArtifactPaths[target] = VisitedArtifact(path: path)
            return path
        } else {
            visitedPrecompiledArtifactPaths[target] = VisitedArtifact(path: nil)
            return nil
        }
    }

    /// Visits bundle targets for marking them not cached. This makes editing resources targets possible when focusing static framework target
    /// - Parameters:
    ///   - dependency: Target that depends on bundle targets
    ///   - graphTraverser: Graph traverser
    ///   - visitedPrecompiledArtifactPaths: Dictionary that keeps record of which target is visited
    private func visitBundleTargets(
        for dependency: GraphDependency,
        graphTraverser: GraphTraverser,
        visitedPrecompiledArtifactPaths: inout [GraphTarget: VisitedArtifact?]
    ) {
        guard let dependencies = graphTraverser.dependencies[dependency] else {
            return
        }

        dependencies
            .compactMap { graphTraverser.target(from: $0) }
            .filter { $0.target.product == .bundle }
            .forEach { target in
                visitedPrecompiledArtifactPaths[target] = VisitedArtifact(path: nil)
            }
    }

    private func mapPrebuiltFrameworks(
        graphDependencies: inout [GraphDependency: Set<GraphDependency>],
        graph: Graph
    ) {
        var graph = graph
        graph.dependencies = graphDependencies
        let graphTraverser = GraphTraverser(graph: graph)

        for (key, value) in graphDependencies {
            guard
                let target = graphTraverser.target(from: key),
                target.target.product.runnable || target.target.product == .unitTests
            else { continue }

            var precompiledDependencies: Set<GraphDependency> = []
            for dependency in value {
                guard
                    let target = graphTraverser.target(from: dependency),
                    target.target.product == .staticFramework
                else { continue }

                let precompiledDependency = graphTraverser.prebuiltDependencies(for: dependency)
                precompiledDependencies.formUnion(precompiledDependency)
            }

            graphDependencies[key] = graphDependencies[key, default: Set()].union(precompiledDependencies)
        }
    }
}
