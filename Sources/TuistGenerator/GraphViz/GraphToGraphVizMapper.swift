import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistGraph

/// Interface that describes a mapper that convers a project graph into a GraphViz graph.
public protocol GraphToGraphVizMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameter graph: ValueGraph to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    func map(graph: ValueGraph, skipTestTargets: Bool, skipExternalDependencies: Bool, targetsToFilter: [String]) -> GraphViz.Graph
}

public final class GraphToGraphVizMapper: GraphToGraphVizMapping {
    public init() {}

    /// Maps the project graph into a GraphViz graph representation.
    ///
    /// - Parameter graph: ValueGraph to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    public func map(graph: ValueGraph, skipTestTargets: Bool, skipExternalDependencies: Bool, targetsToFilter: [String]) -> GraphViz.Graph {
        var nodes: [GraphViz.Node] = []
        var dependencies: [GraphViz.Edge] = []
        var graphVizGraph = GraphViz.Graph(directed: true)

        let graphTraverser = ValueGraphTraverser(graph: graph)

        let filteredTargets: Set<ValueGraphTarget> = graphTraverser.allTargets().filter { target in
            if skipTestTargets, graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name) {
                return false
            }

            if !targetsToFilter.isEmpty, !targetsToFilter.contains(target.target.name) {
                return false
            }

            return true
        }

        let filteredTargetsAndDependencies: Set<ValueGraphTarget> = filteredTargets.union(
            transitiveClosure(Array(filteredTargets)) { target in
                Array(graphTraverser.directTargetDependencies(path: target.path, name: target.target.name))
            }
        )

        filteredTargetsAndDependencies.forEach { target in
            var leftNode = GraphViz.Node(target.target.name)
            leftNode.applyAttributes(attributes: target.styleAttributes)
            nodes.append(leftNode)

            guard
                let targetDependencies = graphTraverser.dependencies[.target(name: target.target.name, path: target.path)]
            else { return }
            targetDependencies
                .filter { dependency in
                    if skipExternalDependencies, dependency.isExternal { return false }
                    return true
                }
                .forEach { dependency in
                    var rightNode = GraphViz.Node(dependency.name)
                    rightNode.applyAttributes(
                        attributes: dependency.styleAttributes(
                            graphTraverser: graphTraverser
                        )
                    )
                    nodes.append(rightNode)
                    let edge = GraphViz.Edge(from: leftNode, to: rightNode)
                    dependencies.append(edge)
                }
        }

        let sortedNodes = Set(nodes).sorted { $0.id < $1.id }
        let sortedDeps = Set(dependencies).sorted { $0.from < $1.from }
        graphVizGraph.append(contentsOf: sortedNodes)
        graphVizGraph.append(contentsOf: sortedDeps)
        return graphVizGraph
    }
}

private extension ValueGraphDependency {
    var isExternal: Bool {
        switch self {
        case .target:
            return false
        case .framework, .xcframework, .library, .packageProduct, .sdk, .cocoapods:
            return true
        }
    }

    var name: String {
        switch self {
        case let .target(name: name, path: _):
            return name
        case let .framework(
            path: path,
            binaryPath: _,
            dsymPath: _,
            bcsymbolmapPaths: _,
            linking: _,
            architectures: _,
            isCarthage: _
        ):
            return path.basenameWithoutExt
        case let .xcframework(
            path: path,
            infoPlist: _,
            primaryBinaryPath: _,
            linking: _
        ):
            return path.basenameWithoutExt
        case let .library(
            path: path,
            publicHeaders: _,
            linking: _,
            architectures: _,
            swiftModuleMap: _
        ):
            return path.basenameWithoutExt
        case let .packageProduct(path: _, product: product):
            return product
        case let .sdk(
            name: name,
            path: _,
            status: _,
            source: _
        ):
            return String(name.split(separator: ".").first ?? "")
        case .cocoapods:
            return "CocoaPods"
        }
    }
}
