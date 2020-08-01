import Foundation
import TuistCore
import GraphViz
import DOT

typealias DotGraph = GraphViz.Graph
public typealias Graph = TuistCore.Graph

/// Interface that describes a mapper that convers a project graph into a dot graph.
protocol GraphToDotGraphMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameter graph: Graph to be converted into a dot graph.
    /// - Returns: The dot graph representation.
    func map(graph: Graph, skipTestTargets: Bool, skipExternalDependencies: Bool) -> DotGraph
}

class GraphToDotGraphMapper: GraphToDotGraphMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameter graph: Graph to be converted into a dot graph.
    /// - Returns: The dot graph representation.
    func map(graph: Graph, skipTestTargets: Bool, skipExternalDependencies: Bool) -> DotGraph {
        var dotGraph = DotGraph(directed: true)
        
        // Targets
        graph.targets.forEach { targetsList in
            targetsList.value.forEach { target in
                if skipTestTargets, target.dependsOnXCTest {
                    return
                }
                if skipExternalDependencies, target.isExternal {
                    return
                }

                dotGraph.append(Node(target.target.name))
                // Dependencies
                target.dependencies.forEach { dependency in
                    if skipExternalDependencies, dependency.isExternal {
                        return
                    }
                    
                    let from = Node(target.name)
                    let to = Node(dependency.name)
                    dotGraph.append(Edge(from: from, to: to))
                        
                    if let sdk = dependency as? SDKNode {
                        dotGraph.append(Node(sdk.name))
                    }
                }
            }
        }

        // Precompiled
        graph.precompiled.forEach { dotGraph.append(Node($0.name)) }
        return dotGraph
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

extension GraphViz.Graph {
    
    var dotRepresentation: String {
        let dot = DOTEncoder().encode(self).sorted()
        return String(dot)
    }
    
}
