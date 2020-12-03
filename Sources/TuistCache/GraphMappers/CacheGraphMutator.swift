import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

/// It defines the interface to mutate a graph using information from the cache.
protocol CacheGraphMutating {
    /// Given a graph an a dictionary whose keys are targets of the graph, and the values are paths
    /// to the .xcframeworks in the cache, it mutates the graph to link the enry nodes against the .xcframeworks instead.
    /// - Parameters:
    ///   - graph: Dependency graph.
    ///   - precompiledFrameworks: Dictionary that maps targets with the paths to their cached `.framework`s or `.xcframework`s.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(graph: Graph, precompiledFrameworks: [TargetNode: AbsolutePath], sources: Set<String>) throws -> Graph
}

class CacheGraphMutator: CacheGraphMutating {
    struct VisitedPrecompiledFramework {
        let path: AbsolutePath?
    }

    // MARK: - Attributes

    /// Utility to parse an .xcframework from the filesystem and load it into memory.
    private let xcframeworkLoader: XCFrameworkNodeLoading

    /// Utility to parse a .framework from the filesystem and load it into memory.
    private let frameworkLoader: FrameworkNodeLoading

    /// Initializes the graph mapper with its attributes.
    /// - Parameter xcframeworkLoader: Utility to parse an .xcframework from the filesystem and load it into memory.
    init(frameworkLoader: FrameworkNodeLoading = FrameworkNodeLoader(),
         xcframeworkLoader: XCFrameworkNodeLoading = XCFrameworkNodeLoader())
    {
        self.frameworkLoader = frameworkLoader
        self.xcframeworkLoader = xcframeworkLoader
    }

    // MARK: - CacheGraphMapping

    public func map(graph: Graph, precompiledFrameworks: [TargetNode: AbsolutePath], sources: Set<String>) throws -> Graph {
        var visitedPrecompiledFrameworkPaths: [TargetNode: VisitedPrecompiledFramework?] = [:]
        var loadedPrecompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
        let userSpecifiedSourceTargets = graph.targets.flatMap(\.value).filter { sources.contains($0.target.name) }
        let userSpecifiedSourceTestTargets = userSpecifiedSourceTargets.flatMap { graph.testTargetsDependingOn(path: $0.path, name: $0.name) }
        var sourceTargets: Set<TargetNode> = Set(userSpecifiedSourceTargets)

        // keep a record of runnable targets that have resources
        // via transitive static dependencies
        let runnableTargetsResources = runnableTargetsToResources(in: graph)
        
        try (userSpecifiedSourceTargets + userSpecifiedSourceTestTargets)
            .forEach { try visit(targetNode: $0,
                                 precompiledFrameworks: precompiledFrameworks,
                                 sources: sources,
                                 sourceTargets: &sourceTargets,
                                 visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                                 loadedPrecompiledNodes: &loadedPrecompiledNodes) }

        // We mark them to be pruned during the tree-shaking
        graph.targets.flatMap(\.value).forEach {
            if !sourceTargets.contains($0) { $0.prune = true }
        }
        
        addResourceTargets(to: runnableTargetsResources)

        return graph
    }
    
    fileprivate func runnableTargetsToResources(in graph: Graph) -> [TargetNode: [TargetNode]] {
        let runnable = graph.targets.flatMap(\.value).filter { $0.target.product.runnable }
        let runnableToResources: [TargetNode: [TargetNode]] = runnable.reduce([:]) { acc, target in
            let resources = graph.resourceBundleDependencies(path: target.path, name: target.name)
            var acc = acc
            acc[target] = resources
            return acc
        }
        return runnableToResources
    }
    
    fileprivate func addResourceTargets(to runnableTargets: [TargetNode: [TargetNode]]) {
        for (runnableTarget, resources) in runnableTargets {
            runnableTarget.dependencies = runnableTarget.dependencies + resources
        }
    }

    fileprivate func visit(targetNode: TargetNode,
                           precompiledFrameworks: [TargetNode: AbsolutePath],
                           sources: Set<String>,
                           sourceTargets: inout Set<TargetNode>,
                           visitedPrecompiledFrameworkPaths: inout [TargetNode: VisitedPrecompiledFramework?],
                           loadedPrecompiledNodes: inout [AbsolutePath: PrecompiledNode]) throws
    {
        sourceTargets.formUnion([targetNode])
        targetNode.dependencies = try mapDependencies(targetNode,
                                                      precompiledFrameworks: precompiledFrameworks,
                                                      sources: sources,
                                                      sourceTargets: &sourceTargets,
                                                      visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                                                      loadedPrecompiledFrameworks: &loadedPrecompiledNodes)
    }

    // swiftlint:disable line_length
    fileprivate func mapDependencies(_ targetNode: TargetNode,
                                     precompiledFrameworks: [TargetNode: AbsolutePath],
                                     sources: Set<String>,
                                     sourceTargets: inout Set<TargetNode>,
                                     visitedPrecompiledFrameworkPaths: inout [TargetNode: VisitedPrecompiledFramework?],
                                     loadedPrecompiledFrameworks: inout [AbsolutePath: PrecompiledNode]) throws -> [GraphNode]
    {
        var newDependencies: [GraphNode] = []
        try targetNode.dependencies.forEach { dependency in
            // If the dependency is not a target node we keep it.
            guard let targetDependency = dependency as? TargetNode else {
                newDependencies.append(dependency)
                return
            }
            
            let isBundleOfStaticTarget = targetDependency.target.product == .bundle && targetNode.target.product.isStatic

            // Transitive bundles
            // get all the transitive bundles
            // declare them as direct dependencies.

            // If the target cannot be replaced with its associated .(xc)framework we return
            guard !sources.contains(targetDependency.target.name), !isBundleOfStaticTarget, let precompiledFrameworkPath = precompiledFrameworkPath(target: targetDependency,
                                                                                                                           precompiledFrameworks: precompiledFrameworks,
                                                                                                                           visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths)
            else {
                sourceTargets.formUnion([targetDependency])
                targetDependency.dependencies = try mapDependencies(targetDependency,
                                                                    precompiledFrameworks: precompiledFrameworks,
                                                                    sources: sources,
                                                                    sourceTargets: &sourceTargets,
                                                                    visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                                                                    loadedPrecompiledFrameworks: &loadedPrecompiledFrameworks)
                newDependencies.append(targetDependency)
                return
            }

            // We load the .framework (or fallback on .xcframework)
            let precompiledFramework: PrecompiledNode = try loadPrecompiledFramework(path: precompiledFrameworkPath, loadedPrecompiledFrameworks: &loadedPrecompiledFrameworks)

            try mapDependencies(targetDependency,
                                precompiledFrameworks: precompiledFrameworks,
                                sources: sources,
                                sourceTargets: &sourceTargets,
                                visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths,
                                loadedPrecompiledFrameworks: &loadedPrecompiledFrameworks).forEach { dependency in
                if let frameworkDependency = dependency as? FrameworkNode {
                    precompiledFramework.add(dependency: PrecompiledNode.Dependency.framework(frameworkDependency))
                } else if let xcframeworkDependency = dependency as? XCFrameworkNode {
                    precompiledFramework.add(dependency: PrecompiledNode.Dependency.xcframework(xcframeworkDependency))
                } else {
                    // Static dependencies fall into this case.
                    // Those are now part of the precompiled (xc)framework and therefore we don't have to link against them.
                }
            }
            newDependencies.append(precompiledFramework)
        }
        return newDependencies
    }

    fileprivate func loadPrecompiledFramework(path: AbsolutePath, loadedPrecompiledFrameworks: inout [AbsolutePath: PrecompiledNode]) throws -> PrecompiledNode {
        if let cachedFramework = loadedPrecompiledFrameworks[path] {
            return cachedFramework
        } else if let framework = try? frameworkLoader.load(path: path) {
            loadedPrecompiledFrameworks[path] = framework
            return framework
        } else {
            let xcframework = try xcframeworkLoader.load(path: path)
            loadedPrecompiledFrameworks[path] = xcframework
            return xcframework
        }
    }

    fileprivate func precompiledFrameworkPath(target: TargetNode,
                                              precompiledFrameworks: [TargetNode: AbsolutePath],
                                              visitedPrecompiledFrameworkPaths: inout [TargetNode: VisitedPrecompiledFramework?]) -> AbsolutePath?
    {
        // Already visited
        if let visited = visitedPrecompiledFrameworkPaths[target] { return visited?.path }

        // The target doesn't have a cached .(xc)framework
        if precompiledFrameworks[target] == nil {
            visitedPrecompiledFrameworkPaths[target] = VisitedPrecompiledFramework(path: nil)
            return nil
        }
        // The target can be replaced
        else if let path = precompiledFrameworks[target],
            target.targetDependencies.allSatisfy({ $0.target.product == .bundle || precompiledFrameworkPath(target: $0,
                                                                                                            precompiledFrameworks: precompiledFrameworks,
                                                                                                            visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths) != nil })
        {
            visitedPrecompiledFrameworkPaths[target] = VisitedPrecompiledFramework(path: path)
            return path
        } else {
            visitedPrecompiledFrameworkPaths[target] = VisitedPrecompiledFramework(path: nil)
            return nil
        }
    }
}
