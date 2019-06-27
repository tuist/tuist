import Foundation

// https://en.wikipedia.org/wiki/DOT_(graph_description_language)
public struct DotGraph: CustomStringConvertible {
    ///  Graph name.
    let name: String

    /// Graph type.
    let type: DotGraphType

    /// Graph nodes.
    let nodes: Set<DotGraphNode>

    /// Graph dependencies.
    let dependencies: [(from: String, to: String)]

    public var description: String {
        let edgeCharacter = (type == .directed) ? "->" : "-"
        let sortedNodes = nodes.sorted(by: { $0.name < $1.name })

        return """
        digraph \"\(name)\" {
        \(sortedNodes.map { "  \($0.description)" }.joined(separator: "\n"))
        
        \(dependencies.map { "  \($0.from) \(edgeCharacter) \($0.to)" }.joined(separator: "\n"))
        }
        """
    }
}
