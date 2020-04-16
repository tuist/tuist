import Basic
import Foundation
import RxSwift
import TuistCore
import TuistSupport

/// It defines the interface to mutate a graph using information from the cache.
protocol CacheGraphMapping {
    /// Given a graph an a dictionary whose keys are targets of the graph, and the values are paths
    /// to the .xcframeworks in the cache, it mutates the graph to link the enry nodes against the .xcframeworks instead.
    /// - Parameters:
    ///   - graph: Dependency graph.
    ///   - xcframeworks: Dictionary that maps targets with the paths to their cached .xcframeworks.
    func map(graph: Graph, xcframeworks: [TargetNode: AbsolutePath]) throws -> Graph
}

class CacheGraphMapper: CacheGraphMapping {
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

    public func map(graph: Graph, xcframeworks: [TargetNode: AbsolutePath]) throws -> Graph {
        var visitedXCFrameworkPaths: [TargetNode: VisitedXCFramework?] = [:]
        var loadedXCFrameworks: [AbsolutePath: XCFrameworkNode] = [:]

        func mapDependencies(_ dependencies: [GraphNode]) throws -> [GraphNode] {
            var newDependencies: [GraphNode] = []
            try dependencies.forEach { dependency in
                // If the dependency is not a target node we keep it.
                guard let targetDependency = dependency as? TargetNode else {
                    newDependencies.append(dependency)
                    return
                }
                // If the target cannot be replace with its associated .xcframework we return
                guard let xcframeworkPath = xcframeworkPath(target: targetDependency,
                                                            xcframeworks: xcframeworks,
                                                            visitedXCFrameworkPaths: &visitedXCFrameworkPaths) else {
                    newDependencies.append(dependency)
                    return
                }

                // We load the xcframework
                let xcframework = try loadXCFramework(path: xcframeworkPath, loadedXCFrameworks: &loadedXCFrameworks)
                try mapDependencies(targetDependency.dependencies).forEach { dependency in
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

        func visit(node: GraphNode) throws {
            guard let targetNode = node as? TargetNode else { return }
            targetNode.dependencies = try mapDependencies(targetNode.dependencies)
        }

        try graph.entryNodes.forEach(visit)

        return graph
    }

    fileprivate func loadXCFramework(path: AbsolutePath, loadedXCFrameworks: inout [AbsolutePath: XCFrameworkNode]) throws -> XCFrameworkNode {
        if let cachedXCFramework = loadedXCFrameworks[path] { return cachedXCFramework }
        let xcframework = try xcframeworkLoader.load(path: path)
        loadedXCFrameworks[path] = xcframework
        return xcframework
    }

    fileprivate func xcframeworkPath(target: TargetNode,
                                     xcframeworks: [TargetNode: AbsolutePath],
                                     visitedXCFrameworkPaths: inout [TargetNode: VisitedXCFramework?]) -> AbsolutePath? {
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
                                                                   visitedXCFrameworkPaths: &visitedXCFrameworkPaths) != nil }) {
            visitedXCFrameworkPaths[target] = VisitedXCFramework(path: path)
            return path
        } else {
            visitedXCFrameworkPaths[target] = VisitedXCFramework(path: nil)
            return nil
        }
    }
}
