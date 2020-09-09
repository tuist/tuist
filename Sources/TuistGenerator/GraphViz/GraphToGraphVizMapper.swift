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

extension GraphViz.Node {
    fileprivate mutating func applyAttributes(attributes: NodeStyleAttributes?) {
        self.fillColor = attributes?.fillColor
        self.strokeWidth = attributes?.strokeWidth
        self.shape = attributes?.shape
    }
}

private struct NodeStyleAttributes {
    let fillColor: GraphViz.Color?
    let strokeWidth: Double?
    let shape: GraphViz.Node.Shape?

    init(colorName: GraphViz.Color.Name? = nil,
         strokeWidth: Double? = nil,
         shape: GraphViz.Node.Shape? = nil) {
        self.fillColor = colorName.map { GraphViz.Color.named($0) }
        self.strokeWidth = strokeWidth
        self.shape = shape
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

    var styleAttributes: NodeStyleAttributes? {
        if self is SDKNode {
            return .init(colorName: .blueviolet, shape: .rectangle)
        }

        if self is CocoaPodsNode {
            return .init(colorName: .red2)
        }

        if self is FrameworkNode {
            return .init(colorName: .darkgoldenrod3, shape: .trapezium)
        }

        if self is LibraryNode {
            return .init(colorName: .lightgray, shape: .folder)
        }

        if self is PackageProductNode {
            return .init(colorName: .tan4, shape: .tab)
        }

        if self is PrecompiledNode {
            return .init(colorName: .skyblue, shape: .trapezium)
        }

        if let targetNode = self as? TargetNode {
            switch targetNode.target.product {
            case .app, .watch2App:
                return .init(colorName: .deepskyblue, strokeWidth: 1.5, shape: .box3d)
            case .appExtension, .watch2Extension:
                return .init(colorName: .deepskyblue2, shape: .component)
            case .framework:
                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .staticLibrary:
//                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .staticFramework:
//                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .dynamicLibrary
//                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .bundle: return .named()
//            case .uiTests, .unitTests
            default: return nil
            }
        }

        return nil
    }
}
