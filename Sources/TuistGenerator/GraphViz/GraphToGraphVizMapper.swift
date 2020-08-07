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

                let leftNode = GraphViz.Node(target.target.name)
                nodes.append(leftNode)

                target.dependencies.forEach { dependency in
                    let rightNode = GraphViz.Node(dependency.name)
                    nodes.append(rightNode)
                    if skipExternalDependencies, dependency.isExternal { return }
                    let edge = GraphViz.Edge(from: leftNode, to: rightNode)
                    dependencies.append(edge)
                }
            }
        }

        graphVizGraph.append(contentsOf: Set(nodes))
        graphVizGraph.append(contentsOf: Set(dependencies))
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
