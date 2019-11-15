import Basic
import Foundation

public class CocoaPodsNode: GraphNode {
    /// Path to the Podfile.
    public var podfilePath: AbsolutePath {
        return path.appending(component: "Podfile")
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

    /// Reads the CocoaPods node. If it it exists in the cache, it returns it from the cache.
    /// Otherwise, it initializes it, stores it in the cache, and then returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the Podfile.
    ///   - cache: Cache instance where the nodes are cached.
    /// - Returns: The initialized instance of the CocoaPods node.
    static func read(path: AbsolutePath,
                     cache: GraphLoaderCaching) -> CocoaPodsNode {
        if let cached = cache.cocoapods(path) { return cached }
        let node = CocoaPodsNode(path: path)
        cache.add(cocoapods: node)
        return node
    }
}
