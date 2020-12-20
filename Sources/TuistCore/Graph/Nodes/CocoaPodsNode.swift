import Foundation
import TSCBasic

@available(*, deprecated, message: "CocoaPods nodes are deprecated. Dependencies should be usted instead with the ValueGraph.")
public class CocoaPodsNode: GraphNode {
    /// Path to the Podfile.
    public var podfilePath: AbsolutePath {
        path.appending(component: "Podfile")
    }

    /// Initializes the node with the path to the directory
    /// that contains the Podfile.
    ///
    /// - Parameter path: Path to the directory that contains the Podfile.
    public init(path: AbsolutePath) {
        super.init(path: path, name: "CocoaPods")
    }

    /// Compares the CocoaPods node with another node and returns true if both nodes are equal.
    ///
    /// - Parameter otherNode: The other node to be compared with.
    /// - Returns: True if the two instances are equal.
    override func isEqual(to otherNode: GraphNode) -> Bool {
        guard let otherTagetNode = otherNode as? CocoaPodsNode else {
            return false
        }
        return super.isEqual(to: otherTagetNode)
    }
}
