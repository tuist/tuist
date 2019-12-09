import Basic
import Foundation
import TuistSupport

public class GraphNode: Equatable, Hashable, Encodable, CustomStringConvertible {
    // MARK: - Attributes

    /// The path to the node.
    public let path: AbsolutePath

    /// The name of the node.
    public let name: String

    /// The description of the node.
    public var description: String { name }

    // MARK: - Init

    public init(path: AbsolutePath, name: String) {
        self.path = path
        self.name = name
    }

    // MARK: - Equatable

    public static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    func isEqual(to otherNode: GraphNode) -> Bool {
        path == otherNode.path &&
            name == otherNode.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(name)
    }
}
