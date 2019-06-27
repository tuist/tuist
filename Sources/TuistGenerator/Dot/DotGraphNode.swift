import Foundation

struct DotGraphNode: CustomStringConvertible, Hashable, Equatable {
    /// Node name.
    let name: String

    /// Node attributes.
    let attributes: Set<DotGraphNodeAttribute>

    /// Returns the string representation of the node.
    var description: String {
        let sortedAttributes = attributes.sorted(by: { $0.description < $1.description })
        let attributesString = "[\(sortedAttributes.map { $0.description }.joined(separator: ", "))]"
        return "\(name) \(attributesString)"
    }

    /// Initializes the node with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the node.
    ///   - attributes: Node attributes.
    init(name: String, attributes: Set<DotGraphNodeAttribute> = Set([])) {
        self.name = name
        self.attributes = attributes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
