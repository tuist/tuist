import Basic
import Foundation
import TuistCore

class GraphNode: Equatable, Hashable, Encodable {
    // MARK: - Attributes

    let path: AbsolutePath
    let name: String

    // MARK: - Init

    init(path: AbsolutePath, name: String) {
        self.path = path
        self.name = name
    }

    // MARK: - Equatable

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        return lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    func isEqual(to otherNode: GraphNode) -> Bool {
        return path == otherNode.path &&
            name == otherNode.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
