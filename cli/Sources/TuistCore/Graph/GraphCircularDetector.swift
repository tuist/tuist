import Path

struct GraphCircularDetectorNode: Hashable, CustomDebugStringConvertible {
    let path: Path.AbsolutePath
    let name: String

    var debugDescription: String {
        "\(path).\(name)"
    }
}

protocol GraphCircularDetecting {
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

    private struct VisitFrame {
        let node: Node
        let successors: [Node]
        var nextSuccessorIndex: Int
    }

    private func visit(
        node: Node,
        inspectedNodes: inout Set<Node>
    ) throws {
        guard !inspectedNodes.contains(node) else {
            return
        }

        var activeNodes = Set<Node>()
        var currentPath: [Node] = []
        var stack = [
            VisitFrame(
                node: node,
                successors: Array(node.to),
                nextSuccessorIndex: 0
            ),
        ]
        activeNodes.insert(node)
        currentPath.append(node)

        while !stack.isEmpty {
            let frameIndex = stack.count - 1
            let frame = stack[frameIndex]

            if frame.nextSuccessorIndex < frame.successors.count {
                let nextNode = frame.successors[frame.nextSuccessorIndex]
                stack[frameIndex].nextSuccessorIndex += 1

                if activeNodes.contains(nextNode) {
                    let cyclePath = currentPath + [nextNode]
                    throw GraphLoadingError.circularDependency(cyclePath.map(\.element))
                }

                guard !inspectedNodes.contains(nextNode) else {
                    continue
                }

                activeNodes.insert(nextNode)
                currentPath.append(nextNode)
                stack.append(
                    VisitFrame(
                        node: nextNode,
                        successors: Array(nextNode.to),
                        nextSuccessorIndex: 0
                    )
                )
            } else {
                inspectedNodes.insert(frame.node)
                activeNodes.remove(frame.node)
                currentPath.removeLast()
                stack.removeLast()
            }
        }
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
