import Foundation
import TSCBasic

struct GraphCircularDetectorNode: Hashable {
    let path: AbsolutePath
    let name: String
}

extension GraphCircularDetectorNode: CustomDebugStringConvertible {
    var debugDescription: String {
        "\(path).\(name)"
    }
}

protocol GraphCircularDetecting: AnyObject {
    func start(from: GraphCircularDetectorNode, to: GraphCircularDetectorNode)
    func complete() throws
}

public final class GraphCircularDetector: GraphCircularDetecting {
    // MARK: - Attributes

    private var nodes = Set<Node>()

    // MARK: - Internal

    func start(from: GraphCircularDetectorNode, to: GraphCircularDetectorNode) {
        let (_, fromNode) = nodes.insert(Node(element: from))
        let (_, toNode) = nodes.insert(Node(element: to))
        fromNode.add(dependency: toNode)
    }

    func complete() throws {
        var inspectedNodes = Set<Node>([])
        while let node = nodes.popFirst() {
            try visit(node: node, inspectedNodes: &inspectedNodes)
        }
    }

    // MARK: - Private

    /// Depth first search to detect cycles
    ///
    /// For a given node, a full path through adjacent nodes is explored one by one.
    ///  - The history of visited nodes along a path is stored in `currentPath`
    ///  - In the event a node we are visiting already exists in `currentPath` we have a cycle!
    ///
    /// To optimize this process, we also keep a list of nodes that had all outgoing paths inspected to completion
    ///  - Nodes that have had all adjacent nodes traversed are added to `inspectedNodes`
    ///  - In the event a node we are visiting already exists in `inspectedNodes` we can skip it
    ///
    /// - Parameter node: The node to visit
    /// - Parameter currentPath: The current path of nodes we are inspecting
    /// - Parameter inspectedNodes: History of nodes that have had all their adjacent nodes traversed to completion
    private func visit(
        node: Node,
        currentPath: OrderedSet<Node> = OrderedSet(),
        inspectedNodes: inout Set<Node>
    ) throws {
        guard !inspectedNodes.contains(node) else {
            return
        }

        if currentPath.contains(node) {
            let cyclePath = currentPath + [node]
            throw GraphLoadingError.circularDependency(cyclePath.map(\.element))
        }

        var currentPath = currentPath
        currentPath.append(node)

        for nextNode in node.to {
            try visit(
                node: nextNode,
                currentPath: currentPath,
                inspectedNodes: &inspectedNodes
            )
        }

        inspectedNodes.insert(node)
    }

    private final class Node: Hashable, CustomDebugStringConvertible {
        let element: GraphCircularDetectorNode
        private(set) var to: Set<Node> = Set([])

        init(element: GraphCircularDetectorNode) {
            self.element = element
        }

        func add(dependency: Node) {
            to.insert(dependency)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(element)
        }

        static func == (lhs: GraphCircularDetector.Node, rhs: GraphCircularDetector.Node) -> Bool {
            lhs.element == rhs.element
        }

        var debugDescription: String {
            "\(element.debugDescription)"
        }
    }
}
