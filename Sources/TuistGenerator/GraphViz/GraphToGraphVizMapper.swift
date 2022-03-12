import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Interface that describes a mapper that converts a project graph into a GraphViz graph.
public protocol GraphToGraphVizMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameter graph: Graph to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    func map(
        graph: TuistGraph.Graph,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        targetsToFilter: [String]
    ) -> GraphViz.Graph
}

public final class GraphToGraphVizMapper: GraphToGraphVizMapping {
    public init() {}

    /// Maps the project graph into a GraphViz graph representation.
    ///
    /// - Parameter graph: Graph to be converted into a GraphViz.Graph.
    /// - Returns: The GraphViz.Graph representation.
    public func map(
        graph: TuistGraph.Graph,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        targetsToFilter: [String]
    ) -> GraphViz.Graph {
        var nodes: [GraphViz.Node] = []
        var dependencies: [GraphViz.Edge] = []
        var graphVizGraph = GraphViz.Graph(directed: true)

        let graphTraverser = GraphTraverser(graph: graph)

        let allTargets: Set<GraphTarget> = skipExternalDependencies ? graphTraverser.allInternalTargets() : graphTraverser
            .allTargets()
        let filteredTargets: Set<GraphTarget> = allTargets.filter { target in
            if skipTestTargets, graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name) {
                return false
            }

            if !targetsToFilter.isEmpty, !targetsToFilter.contains(target.target.name) {
                return false
            }

            return true
        }

        let filteredTargetsAndDependencies: Set<GraphTarget> = filteredTargets.union(
            transitiveClosure(Array(filteredTargets)) { target in
                Array(graphTraverser.directTargetDependencies(path: target.path, name: target.target.name))
            }
        )

        filteredTargetsAndDependencies.forEach { target in
            if skipExternalDependencies, target.project.isExternal { return }

            var leftNode = GraphViz.Node(target.target.name)

            leftNode.applyAttributes(attributes: target.styleAttributes)
            nodes.append(leftNode)

            guard let targetDependencies = graphTraverser.dependencies[.target(name: target.target.name, path: target.path)]
            else { return }

            targetDependencies
                .filter { dependency in
                    if skipExternalDependencies, dependency.isExternal(graph.projects) { return false }
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

extension GraphDependency {
    fileprivate func isExternal(_ projects: [AbsolutePath: Project]) -> Bool {
        switch self {
        case let .target(_, path):
            return projects[path]?.isExternal ?? false
        case .framework, .xcframework, .library, .bundle, .packageProduct, .sdk:
            return true
        }
    }

    fileprivate var name: String {
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
        case let .bundle(path):
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
        }
    }
}
