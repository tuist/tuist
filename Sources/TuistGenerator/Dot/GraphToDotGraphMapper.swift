import Foundation
import TuistCore

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
        var nodes: [DotGraphNode] = []
        var dependencies: [DotGraphDependency] = []

        // Targets
        graph.targets.forEach { targetsList in
            targetsList.value.forEach { target in
                if skipTestTargets, target.dependsOnXCTest {
                    return
                }
                if skipExternalDependencies, target.isExternal {
                    return
                }

                nodes.append(DotGraphNode(name: target.target.name))

                // Dependencies
                target.dependencies.forEach { dependency in
                    if skipExternalDependencies, dependency.isExternal {
                        return
                    }

                    dependencies.append(DotGraphDependency(from: target.name, to: dependency.name))

                    if let sdk = dependency as? SDKNode {
                        nodes.append(DotGraphNode(name: sdk.name))
                    }
                }
            }
        }

        // Precompiled
        graph.precompiled.forEach { nodes.append(DotGraphNode(name: $0.name)) }

        return DotGraph(name: "Project Dependencies Graph",
                        type: .directed,
                        nodes: Set(nodes),
                        dependencies: Set(dependencies))
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
