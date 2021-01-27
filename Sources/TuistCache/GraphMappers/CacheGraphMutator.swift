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
    ///   - precompiledTargets: Dictionary that maps targets with the paths to their cached `.framework`s or `.xcframework`s.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(graph: ValueGraph, precompiledTargets: [ValueGraphTarget: AbsolutePath], sources: Set<String>) throws -> ValueGraph
}

class CacheGraphMutator: CacheGraphMutating {
    struct VisitedPrecompiledDependency {
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

    public func map(graph: ValueGraph, precompiledTargets: [ValueGraphTarget: AbsolutePath], sources: Set<String>) throws -> ValueGraph {
        let graphTraverser = ValueGraphTraverser(graph: graph)

        /// This dictionary keeps tracks of the pre-compiled targets of the graph that have already been visited to avoid
        /// redundant traverses.
        var visitedPrecompiledTargets: [ValueGraphTarget: VisitedPrecompiledDependency] = [:]

        /// Since pre-compiled targets need metadata when inserted in the graph (e.g. linking, architecture), this dictionary
        /// caches the loaded pre-compiled targets after loading them to avoid unnecessary IO.
        var loadedPrecompiledTargets: [AbsolutePath: ValueGraphDependency] = [:]

        /// A dictionary that contains the new targets that should be in the graph after replacing some of them with their pre-compiled version.
        var mappedTargets: [AbsolutePath: [String: Target]] = [:]
        
        /// A dictionary that contains the new dependency graph after replacing some nodes with their pre-compiled version.
        var mappedDependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [:]
        

        try self.sourceTargets(graphTraverser: graphTraverser, sources: sources).forEach {
            try visit(target: $0,
                      precompiledTargets: precompiledTargets,
                      sources: sources,
                      graph: graph,
                      mappedTargets: &mappedTargets,
                      mappedDependencies: &mappedDependencies,
                      visitedPrecompiledTargets: &visitedPrecompiledTargets,
                      loadedPrecompiledTargets: &loadedPrecompiledTargets)
        }
        
        var graph = graph
        graph.targets = mappedTargets
        graph.dependencies = mappedDependencies
    
        return graph
    }

    fileprivate func visit(target: ValueGraphTarget,
                           precompiledTargets : [ValueGraphTarget: AbsolutePath],
                           sources: Set<String>,
                           graph: ValueGraph,
                           mappedTargets: inout [AbsolutePath: [String: Target]],
                           mappedDependencies: inout [ValueGraphDependency: Set<ValueGraphDependency>],
                           visitedPrecompiledTargets: inout [ValueGraphTarget: VisitedPrecompiledDependency],
                           loadedPrecompiledTargets: inout [AbsolutePath: ValueGraphDependency]) throws
    {
        // Target
        var projectTargets = mappedTargets[target.path, default: [:]]
        projectTargets[target.target.name] = target.target
        mappedTargets[target.path] = projectTargets
        
        // Dependencies
        var mappedTargetDependencies = mappedDependencies[ValueGraphDependency.target(name: target.target.name, path: target.path), default: Set()]
        var targetDependencies = graph.dependencies[ValueGraphDependency.target(name: target.target.name, path: target.path), default: Set()]
        
        targetDependencies.forEach { (targetDependency) in
            // Pre-compiled dependency (e.g. xcframework, framework, library)
            guard case let ValueGraphDependency.target(targetDependencyName, targetDependencyPath) = targetDependency else  {
                mappedTargetDependencies.formUnion([targetDependency])
            }
            
            let shouldRemainAsSources = sources.contains(targetDependencyName)
            let precompiledTargetPath = precompiledFrameworkPath(target: <#T##TargetNode#>, precompiledFrameworks: <#T##[TargetNode : AbsolutePath]#>, visitedPrecompiledFrameworkPaths: &<#T##<<error type>>#>)
            
        }
        try dependencies.forEach { dependency in
  

            // Transitive bundles
            // get all the transitive bundles
            // declare them as direct dependencies.

            // If the target cannot be replaced with its associated .(xc)framework we return
            guard !sources.contains(targetDependency.target.name), let precompiledFrameworkPath = precompiledFrameworkPath(target: targetDependency,
                                                                                                                           precompiledFrameworks: precompiledFrameworks,
                                                                                                                           visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths)
            else {
                sourceTargets.formUnion([targetDependency])
                targetDependency.dependencies = try mapDependencies(targetDependency.dependencies,
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

            try mapDependencies(targetDependency.dependencies,
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
    
    


    fileprivate func loadedPrecompiledDependency(path: AbsolutePath,
                                              loadedPrecompiledTargets: inout [AbsolutePath: ValueGraphDependency]) throws -> ValueGraphDependency
    {
        if let loadedDependency = loadedPrecompiledTargets[path] {
            return loadedDependency
        } else if let framework = try? frameworkLoader.load(path: path) {
            
            
            loadedPrecompiledFrameworks[path] = framework
            return framework
        } else {
            let xcframework = try xcframeworkLoader.load(path: path)
            loadedPrecompiledFrameworks[path] = xcframework
            return xcframework
        }
    }

    /// Returns the list of targets and its dependents that should remain as sources.
    /// - Parameters:
    ///   - graphTraverser: Graph traverser instance.
    ///   - sources: List of targets that should remain as sources.
    /// - Returns: List of targets and its dependents that should remain as sources.
    fileprivate func sourceTargets(graphTraverser: GraphTraversing, sources: Set<String>) -> Set<ValueGraphTarget> {
        let sourceTargets = graphTraverser.allTargets().filter { sources.contains($0.target.name) }
        let sourceDependentTargets = sourceTargets.flatMap { graphTraverser.testTargetsDependingOn(path: $0.path, name: $0.target.name) }
        return Set(sourceTargets + sourceDependentTargets)
    }

    fileprivate func precompiledTargetPath(target: ValueGraphTarget,
                                           precompiledTargets : [ValueGraphTarget: AbsolutePath],
                                           visitedPrecompiledTargets: inout [ValueGraphTarget: VisitedPrecompiledDependency?]) -> AbsolutePath?
    {
        // Already visited
        if let visited = visitedPrecompiledTargets[target] { return visited?.path }
        
        // The target doesn't have a cached pre-compiled version
        if precompiledTargets[target] == nil {
            visitedPrecompiledTargets[target] = VisitedPrecompiledDependency(path: nil)
            return nil
        }
        // The target can be replaced
        else if let path = precompiledTargets[target],
                target.targetDependencies.allSatisfy({ precompiledFrameworkPath(target: $0,
                                                                                precompiledFrameworks: precompiledFrameworks,
                                                                                visitedPrecompiledFrameworkPaths: &visitedPrecompiledFrameworkPaths) != nil })
        {
            visitedPrecompiledTargets[target] = VisitedPrecompiledDependency(path: path)
            return path
        } else {
            visitedPrecompiledTargets[target] = VisitedPrecompiledDependency(path: nil)
            return nil
        }
    }
}
