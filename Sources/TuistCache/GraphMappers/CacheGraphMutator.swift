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
    ///   - xcframeworks: Dictionary that maps targets with the paths to their cached .xcframeworks.
    ///   - source: Contains a list of targets that won't be replaced with their pre-compiled version from the cache.
    func map(graph: Graph, xcframeworks: [TargetNode: AbsolutePath], sources: Set<String>) throws -> Graph
}

class CacheGraphMutator: CacheGraphMutating {
    struct VisitedXCFramework {
        let path: AbsolutePath?
    }

    // MARK: - Attributes

    /// Utility to parse an .xcframework from the filesystem and load it into memory.
    private let xcframeworkLoader: XCFrameworkNodeLoading

    /// Initializes the graph mapper with its attributes.
    /// - Parameter xcframeworkLoader: Utility to parse an .xcframework from the filesystem and load it into memory.
    init(xcframeworkLoader: XCFrameworkNodeLoading = XCFrameworkNodeLoader()) {
        self.xcframeworkLoader = xcframeworkLoader
    }

    // MARK: - CacheGraphMapping

    public func map(graph: Graph, xcframeworks: [TargetNode: AbsolutePath], sources: Set<String>) throws -> Graph {
        var visitedXCFrameworkPaths: [TargetNode: VisitedXCFramework?] = [:]
        var loadedXCFrameworks: [AbsolutePath: XCFrameworkNode] = [:]
        var sourceTargets: Set<TargetNode> = Set()

        try graph.entryNodes.compactMap { $0 as? TargetNode }
            .forEach { try visit(targetNode: $0,
                                 xcframeworks: xcframeworks,
                                 sources: sources,
                                 sourceTargets: &sourceTargets,
                                 visitedXCFrameworkPaths: &visitedXCFrameworkPaths,
                                 loadedXCFrameworks: &loadedXCFrameworks) }

        return treeShake(graph: graph, sourceTargets: sourceTargets)
    }

    fileprivate func visit(targetNode: TargetNode,
                           xcframeworks: [TargetNode: AbsolutePath],
                           sources: Set<String>,
                           sourceTargets: inout Set<TargetNode>,
                           visitedXCFrameworkPaths: inout [TargetNode: VisitedXCFramework?],
                           loadedXCFrameworks: inout [AbsolutePath: XCFrameworkNode]) throws
    {
        sourceTargets.formUnion([targetNode])
        targetNode.dependencies = try mapDependencies(targetNode.dependencies,
                                                      xcframeworks: xcframeworks,
                                                      sources: sources,
                                                      sourceTargets: &sourceTargets,
                                                      visitedXCFrameworkPaths: &visitedXCFrameworkPaths,
                                                      loadedXCFrameworks: &loadedXCFrameworks)
    }

    fileprivate func mapDependencies(_ dependencies: [GraphNode],
                                     xcframeworks: [TargetNode: AbsolutePath],
                                     sources: Set<String>,
                                     sourceTargets: inout Set<TargetNode>,
                                     visitedXCFrameworkPaths: inout [TargetNode: VisitedXCFramework?],
                                     loadedXCFrameworks: inout [AbsolutePath: XCFrameworkNode]) throws -> [GraphNode]
    {
        var newDependencies: [GraphNode] = []
        try dependencies.forEach { dependency in
            // If the dependency is not a target node we keep it.
            guard let targetDependency = dependency as? TargetNode else {
                newDependencies.append(dependency)
                return
            }

            // If the target cannot be replaced with its associated .xcframework we return
            guard !sources.contains(targetDependency.target.name), let xcframeworkPath = xcframeworkPath(target: targetDependency,
                                                                                                         xcframeworks: xcframeworks,
                                                                                                         visitedXCFrameworkPaths: &visitedXCFrameworkPaths)
            else {
                sourceTargets.formUnion([targetDependency])
                targetDependency.dependencies = try mapDependencies(targetDependency.dependencies,
                                                                    xcframeworks: xcframeworks,
                                                                    sources: sources,
                                                                    sourceTargets: &sourceTargets,
                                                                    visitedXCFrameworkPaths: &visitedXCFrameworkPaths,
                                                                    loadedXCFrameworks: &loadedXCFrameworks)
                newDependencies.append(targetDependency)
                return
            }

            // We load the xcframework
            let xcframework = try self.loadXCFramework(path: xcframeworkPath, loadedXCFrameworks: &loadedXCFrameworks)
            try mapDependencies(targetDependency.dependencies,
                                xcframeworks: xcframeworks,
                                sources: sources,
                                sourceTargets: &sourceTargets,
                                visitedXCFrameworkPaths: &visitedXCFrameworkPaths,
                                loadedXCFrameworks: &loadedXCFrameworks).forEach { dependency in
                if let frameworkDependency = dependency as? FrameworkNode {
                    xcframework.add(dependency: XCFrameworkNode.Dependency.framework(frameworkDependency))
                } else if let xcframeworkDependency = dependency as? XCFrameworkNode {
                    xcframework.add(dependency: XCFrameworkNode.Dependency.xcframework(xcframeworkDependency))
                } else {
                    // Static dependencies fall into this case.
                    // Those are now part of the precompiled xcframework and therefore we don't have to link against them.
                }
            }
            newDependencies.append(xcframework)
        }
        return newDependencies
    }

    func treeShake(graph: Graph, sourceTargets: Set<TargetNode>) -> Graph {
        let entryProjects = Set(graph.entryNodes.compactMap { $0 as? TargetNode }.map { $0.project })
        let targetReferences = Set(sourceTargets.map { TargetReference(projectPath: $0.path, name: $0.name) })

        let projects = graph.projects.compactMap { (project) -> Project? in
            if entryProjects.contains(project) {
                return project
            } else {
                let targets: [Target] = project.targets.compactMap { (target) -> Target? in
                    guard let targetNode = graph.target(path: project.path, name: target.name) else { return nil }
                    guard sourceTargets.contains(targetNode) else { return nil }
                    return target
                }
                if targets.isEmpty {
                    return nil
                } else {
                    let schemes: [Scheme] = project.schemes.compactMap { scheme -> Scheme? in
                        let buildActionTargets = scheme.buildAction?.targets.filter { targetReferences.contains($0) } ?? []

                        // The scheme contains no buildable targets so we don't include it.
                        if buildActionTargets.isEmpty { return nil }

                        let testActionTargets = scheme.testAction?.targets.filter { targetReferences.contains($0.target) } ?? []
                        var scheme = scheme
                        var buildAction = scheme.buildAction
                        var testAction = scheme.testAction
                        buildAction?.targets = buildActionTargets
                        testAction?.targets = testActionTargets
                        scheme.buildAction = buildAction
                        scheme.testAction = testAction

                        return scheme
                    }
                    return project.with(targets: targets).with(schemes: schemes)
                }
            }
        }

        return graph
            .with(projects: projects)
            .with(targets: sourceTargets.reduce(into: [AbsolutePath: [TargetNode]]()) { acc, target in
                var targets = acc[target.path, default: []]
                targets.append(target)
                acc[target.path] = targets
            })
    }

    fileprivate func loadXCFramework(path: AbsolutePath, loadedXCFrameworks: inout [AbsolutePath: XCFrameworkNode]) throws -> XCFrameworkNode {
        if let cachedXCFramework = loadedXCFrameworks[path] { return cachedXCFramework }
        let xcframework = try xcframeworkLoader.load(path: path)
        loadedXCFrameworks[path] = xcframework
        return xcframework
    }

    fileprivate func xcframeworkPath(target: TargetNode,
                                     xcframeworks: [TargetNode: AbsolutePath],
                                     visitedXCFrameworkPaths: inout [TargetNode: VisitedXCFramework?]) -> AbsolutePath?
    {
        // Already visited
        if let visited = visitedXCFrameworkPaths[target] { return visited?.path }

        // The target doesn't have a cached xcframework
        if xcframeworks[target] == nil {
            visitedXCFrameworkPaths[target] = VisitedXCFramework(path: nil)
            return nil
        }
        // The target can be replaced
        else if let path = xcframeworks[target],
            target.targetDependencies.allSatisfy({ xcframeworkPath(target: $0, xcframeworks: xcframeworks,
                                                                   visitedXCFrameworkPaths: &visitedXCFrameworkPaths) != nil })
        {
            visitedXCFrameworkPaths[target] = VisitedXCFramework(path: path)
            return path
        } else {
            visitedXCFrameworkPaths[target] = VisitedXCFramework(path: nil)
            return nil
        }
    }
}
