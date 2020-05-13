import Foundation

/// Dependency between two nodes of the dot graph.
struct DotGraphDependency: Equatable, Hashable {
    let from: String
    let to: String
}

// https://en.wikipedia.org/wiki/DOT_(graph_description_language)
struct DotGraph: Equatable, CustomStringConvertible {
    ///  Graph name.
    let name: String

    /// Graph type.
    let type: DotGraphType

    /// Graph nodes.
    let nodes: Set<DotGraphNode>

    /// Graph dependencies.
    let dependencies: Set<DotGraphDependency>

    // MARK: - CustomStringConvertible

    public var description: String {
        let edgeCharacter = (type == .directed) ? "->" : "-"
        let sortedNodes = nodes.sorted(by: { $0.name < $1.name })
        let sortedDependencies = dependencies.sorted(by: { $0.from < $1.from })

        return """
        digraph \"\(name)\" {
        \(sortedNodes.map { "  \($0.description)" }.joined(separator: "\n"))

        \(sortedDependencies.map { "  \"\($0.from)\" \(edgeCharacter) \"\($0.to)\"" }.joined(separator: "\n"))
        }
        """
    }
}
