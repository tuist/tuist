import Foundation
import GraphViz
import TuistCore
import TuistSupport
import XcodeGraph

/// Interface that describes a mapper that converts a project graph into a GraphViz graph.
public protocol GraphToGraphVizMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameters
    ///  - graph: Graph to be used for attributing
    ///  - targetsAndDependencies: Targets to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    func map(
        graph: XcodeGraph.Graph,
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>]
    ) -> GraphViz.Graph
}

public final class GraphToGraphVizMapper: GraphToGraphVizMapping {
    public init() {}

    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameters
    ///  - graph: Graph to be used for attributing
    ///  - targetsAndDependencies: Targets to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation
    public func map(
        graph: XcodeGraph.Graph,
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>]
    ) -> GraphViz.Graph {
        var nodes: [GraphViz.Node] = []
        var dependencies: [GraphViz.Edge] = []
        var graphVizGraph = GraphViz.Graph(directed: true)

        let graphTraverser = GraphTraverser(graph: graph)

        for (target, targetDependencies) in targetsAndDependencies {
            var leftNode = GraphViz.Node(target.target.name)

            leftNode.applyAttributes(attributes: target.styleAttributes)
            nodes.append(leftNode)

            for dependency in targetDependencies {
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

extension GraphDependency {
    fileprivate var name: String {
        switch self {
        case let .target(name: name, path: _, status: _):
            return name
        case let .framework(
            path: path,
            binaryPath: _,
            dsymPath: _,
            bcsymbolmapPaths: _,
            linking: _,
            architectures: _,
            status: _
        ):
            return path.basenameWithoutExt
        case let .xcframework(xcframework):
            return xcframework.path.basenameWithoutExt
        case let .library(
            path: path,
            publicHeaders: _,
            linking: _,
            architectures: _,
            swiftModuleMap: _
        ):
            return path.basenameWithoutExt
        case let .bundle(path):
            return path.basenameWithoutExt
        case let .packageProduct(path: _, product: product, type: _):
            return product
        case let .sdk(
            name: name,
            path: _,
            status: _,
            source: _
        ):
            return String(name.split(separator: ".").first ?? "")
        case let .macro(path):
            return path.basename
        }
    }
}
