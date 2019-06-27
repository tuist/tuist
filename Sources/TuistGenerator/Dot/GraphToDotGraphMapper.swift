import Foundation

/// Interface t
protocol GraphToDotGraphMapping {}

class GraphToDotGraphMapper: GraphToDotGraphMapping {
    /// Maps the project graph into a dot graph representation.
    ///
    /// - Parameter graph: Graph to be converted into a dot graph.
    /// - Returns: The dot graph representation.
    func map(graph: Graph) -> DotGraph {
        var nodes: [DotGraphNode] = []
        var dependencies: [DotGraphDependency] = []

        // Targets
        graph.targets.forEach { target in
            nodes.append(DotGraphNode(name: target.target.name))

            // Dependencies
            target.dependencies.forEach { dependency in
                dependencies.append(DotGraphDependency(from: target.name, to: dependency.name))

                if let sdk = dependency as? SDKNode {
                    nodes.append(DotGraphNode(name: sdk.name))
                }
            }
        }

        // Precompiled
        graph.precompiled.forEach { precompiled in
            nodes.append(DotGraphNode(name: precompiled.name))
        }

        return DotGraph(name: "Project Dependencies Graph",
                        type: .directed,
                        nodes: Set(nodes),
                        dependencies: Set(dependencies))
    }
}
