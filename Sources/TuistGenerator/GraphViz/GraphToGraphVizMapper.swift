import Foundation
import GraphViz
import TuistCore

/// Interface that describes a mapper that convers a project graph into a GraphViz graph.
protocol GraphToGraphVizMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameter graph: Graph to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    func map(graph: TuistCore.Graph, skipTestTargets: Bool, skipExternalDependencies: Bool) -> GraphViz.Graph
}

final class GraphToGraphVizMapper: GraphToGraphVizMapping {
    /// Maps the project graph into a GraphViz graph representation.
    ///
    /// - Parameter graph: TuistCore.Graph to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    func map(graph: TuistCore.Graph, skipTestTargets: Bool, skipExternalDependencies: Bool) -> GraphViz.Graph {
        var nodes: [GraphViz.Node] = []
        var dependencies: [GraphViz.Edge] = []
        var graphVizGraph = GraphViz.Graph(directed: true)

        graph.targets.forEach { targetsList in
            targetsList.value.forEach { target in
                if skipTestTargets, target.dependsOnXCTest {
                    return
                }
                if skipExternalDependencies, target.isExternal {
                    return
                }

                var leftNode = GraphViz.Node(target.target.name)
                leftNode.applyAttributes(attributes: target.styleAttributes)
                nodes.append(leftNode)

                target.dependencies.forEach { dependency in
                    var rightNode = GraphViz.Node(dependency.name)
                    rightNode.applyAttributes(attributes: dependency.styleAttributes)
                    nodes.append(rightNode)
                    if skipExternalDependencies, dependency.isExternal { return }
                    let edge = GraphViz.Edge(from: leftNode, to: rightNode)
                    dependencies.append(edge)
                }
            }
        }

        let sortedNodes = Set(nodes).sorted { $0.id < $1.id }
        let sortedDeps = Set(dependencies).sorted { $0.from < $1.from }
        graphVizGraph.append(contentsOf: sortedNodes)
        graphVizGraph.append(contentsOf: sortedDeps)
        return graphVizGraph
    }
}

private extension GraphNode {
    var isExternal: Bool {
        if self is SDKNode {
            return true
        }
        if self is CocoaPodsNode {
            return true
        }
        if self is FrameworkNode {
            return true
        }
        if self is LibraryNode {
            return true
        }
        if self is PackageProductNode {
            return true
        }
        if self is PrecompiledNode {
            return true
        }

        return false
    }
}
