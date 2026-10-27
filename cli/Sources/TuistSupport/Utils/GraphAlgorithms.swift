private struct TopologicalSortFrame<Node> {
    let node: Node
    let successors: [Node]
    var nextSuccessorIndex: Int
}

public enum GraphAlgorithmError: Error, Equatable {
    case unexpectedCycle
}

/// Perform a topological sort of a graph.
///
/// The implementation mirrors TSCBasic's reverse-postorder DFS behavior while
/// using an explicit stack to avoid overflowing the call stack on deep graphs.
public func topologicalSort<T: Hashable>(
    _ nodes: [T],
    successors: (T) throws -> [T]
) throws -> [T] {
    var visited = Set<T>()
    var active = Set<T>()
    var result: [T] = []

    for node in nodes {
        guard visited.insert(node).inserted else {
            continue
        }

        active.insert(node)
        var stack = [
            TopologicalSortFrame(
                node: node,
                successors: try successors(node),
                nextSuccessorIndex: 0
            ),
        ]

        while !stack.isEmpty {
            let frameIndex = stack.count - 1
            let frame = stack[frameIndex]

            if frame.nextSuccessorIndex < frame.successors.count {
                let successor = frame.successors[frame.nextSuccessorIndex]
                stack[frameIndex].nextSuccessorIndex += 1

                if active.contains(successor) {
                    throw GraphAlgorithmError.unexpectedCycle
                }

                if visited.insert(successor).inserted {
                    active.insert(successor)
                    stack.append(
                        TopologicalSortFrame(
                            node: successor,
                            successors: try successors(successor),
                            nextSuccessorIndex: 0
                        )
                    )
                }
            } else {
                result.append(frame.node)
                active.remove(frame.node)
                stack.removeLast()
            }
        }
    }

    return result.reversed()
}
