import Basic
import Foundation

struct GraphCircularDetectorNode: Hashable {
    let path: AbsolutePath
    let name: String
}

protocol GraphCircularDetecting: AnyObject {
    // swiftlint:disable:next identifier_name
    func start(from: GraphCircularDetectorNode, to: GraphCircularDetectorNode) throws
    func complete(_ node: GraphCircularDetectorNode)
}

final class GraphCircularDetector: GraphCircularDetecting {
    // MARK: - Attributes

    var edges: [GraphCircularDetectorNode: [GraphCircularDetectorNode]] = [:]

    // MARK: - Internal

    // swiftlint:disable:next identifier_name
    func start(from: GraphCircularDetectorNode, to: GraphCircularDetectorNode) throws {
        if edges[to] != nil {
            throw GraphLoadingError.circularDependency(from, to)
        } else {
            var nodes = edges[from]
            if nodes == nil { nodes = [] }
            nodes?.append(to)
            edges[from] = nodes
        }
    }

    func complete(_ node: GraphCircularDetectorNode) {
        let nodes = edges[node]
        edges.removeValue(forKey: node)
        nodes?.forEach({ complete($0) })
    }
}
