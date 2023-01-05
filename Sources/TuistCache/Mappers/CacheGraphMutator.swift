import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// It defines the interface to mutate a graph using information from the cache.
protocol CacheGraphMutating {
    /// It returns the input graph having all replaceable targets replaced with their precompiled version.
    /// Replaced targets are marked as to be pruned.
    /// - Parameters:
    ///   - graph: Dependency graph.
    ///   - precompiledArtifacts: Dictionary that maps targets with the paths to their cached `.framework`s, `.xcframework`s or `.bundle`s.
    ///   - sources: Contains a list of targets that won't be replaced with their precompiled version from the cache.
    func map(graph: Graph, precompiledArtifacts: [GraphTarget: AbsolutePath], sources: Set<String>) throws -> Graph
}

class CacheGraphMutator: CacheGraphMutating {
    /// Utility to load artifacts from the filesystem and load it into memory.
    private let artifactLoader: ArtifactLoading

    init(artifactLoader: ArtifactLoading = CachedArtifactLoader()) {
        self.artifactLoader = artifactLoader
    }

    func map(
        graph oldGraph: Graph,
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        sources: Set<String>
    ) throws -> Graph {
        guard !precompiledArtifacts.isEmpty else { return oldGraph }

        let graphTraverser = GraphTraverser(graph: oldGraph)

        let replaceableTargets = try makeReplaceableTargets(
            precompiledArtifacts: precompiledArtifacts,
            sources: sources,
            graphTraverser: graphTraverser
        )

        var newGraph = oldGraph
        newGraph.dependencies = try mapDependencies(
            replaceableTargets: replaceableTargets,
            precompiledArtifacts: precompiledArtifacts,
            graphTraverser: graphTraverser
        )
        newGraph.targets = mapTargets(
            replaceableTargets: replaceableTargets,
            graphTraverser: graphTraverser
        )
        return newGraph
    }

    fileprivate func makeReplaceableTargets(
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        sources: Set<String>,
        graphTraverser: GraphTraversing
    ) throws -> Set<GraphTarget> {
        let allTargets = graphTraverser.allTargets()
        let sortedCacheableTargets = try graphTraverser.allTargetsTopologicalSorted()
        let userSpecifiedSourceTargets = allTargets.filter { sources.contains($0.target.name) }

        // Targets are sorted in topological order, so we start analysing from the targets with less dependencies.
        // Because of this, we will need to check only the direct dependencies (instead of all the transitives dependencies).
        // A target will be considered as "replaceable", if:
        // * There is a precompiled artifact
        // * Does not belong to the list of user specified source targets
        // * Its direct dependencies are all replaceable
        var replaceableTargets = Set<GraphTarget>()
        for target in sortedCacheableTargets {
            let isPrecompiledTarget = precompiledArtifacts[target] != nil
            guard isPrecompiledTarget else { continue }

            let isUserSpecifiedSourceTarget = userSpecifiedSourceTargets.contains(target)
            guard !isUserSpecifiedSourceTarget else { continue }

            let directTargetDependencies = graphTraverser.directTargetDependencies(path: target.path, name: target.target.name)
            let allDirectTargetDependenciesCanBeReplaced = directTargetDependencies.allSatisfy { replaceableTargets.contains($0) }
            if allDirectTargetDependenciesCanBeReplaced {
                replaceableTargets.insert(target)
            }
        }

        // A bundle that belongs to a non replaceable target must be treated as non replaceable.
        // This makes editing resources targets possible when focusing static framework target.
        let nonReplaceableTargets = allTargets.subtracting(replaceableTargets)
        let nonReplaceableBundles = nonReplaceableTargets
            .flatMap { target in graphTraverser.directTargetDependencies(path: target.path, name: target.target.name) }
            .filter { $0.target.product == .bundle }
        replaceableTargets.subtract(nonReplaceableBundles)

        return replaceableTargets
    }

    fileprivate func mapDependencies(
        replaceableTargets: Set<GraphTarget>,
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        graphTraverser: GraphTraverser
    ) throws -> [GraphDependency: Set<GraphDependency>] {
        var graphDependencies = [GraphDependency: Set<GraphDependency>]()
        for (graphTarget, oldDependencies) in graphTraverser.dependencies {
            let newDependencies = try oldDependencies.map { dependency in
                try mapReplaceableTargetIfNeeded(
                    graphTarget: dependency,
                    replaceableTargets: replaceableTargets,
                    precompiledArtifacts: precompiledArtifacts,
                    graphTraverser: graphTraverser
                )
            }

            let newTarget = try mapReplaceableTargetIfNeeded(
                graphTarget: graphTarget,
                replaceableTargets: replaceableTargets,
                precompiledArtifacts: precompiledArtifacts,
                graphTraverser: graphTraverser
            )
            graphDependencies[newTarget] = Set(newDependencies)
        }
        return graphDependencies
    }

    fileprivate func mapTargets(
        replaceableTargets: Set<GraphTarget>,
        graphTraverser: GraphTraversing
    ) -> [AbsolutePath: [String: Target]] {
        var targets = graphTraverser.targets
        // If target is replaceable we mark it to be pruned during the tree-shaking
        for graphTarget in graphTraverser.allTargets() where replaceableTargets.contains(graphTarget) {
            targets[graphTarget.path]?[graphTarget.target.name]?.prune = true
        }
        return targets
    }

    fileprivate func mapReplaceableTargetIfNeeded(
        graphTarget: GraphDependency,
        replaceableTargets: Set<GraphTarget>,
        precompiledArtifacts: [GraphTarget: AbsolutePath],
        graphTraverser: GraphTraverser
    ) throws -> GraphDependency {
        guard let target = graphTraverser.target(from: graphTarget),
              replaceableTargets.contains(target)
        else {
            // Target is not replaceable, we keep it as is.
            return graphTarget
        }

        // Target is replaceable, load the .framework or .xcframework or .bundle
        return try artifactLoader.load(path: precompiledArtifacts[target]!)
    }
}
