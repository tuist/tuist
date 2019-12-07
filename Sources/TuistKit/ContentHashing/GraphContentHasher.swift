import Foundation
import TuistCore

public protocol GraphContentHashing {
    func contentHashes(for graph: Graphing) -> Dictionary<TargetNode, Int>
}

public final class GraphContentHasher: GraphContentHashing {
    public init() {}
    
    public func contentHashes(for graph: Graphing) -> Dictionary<TargetNode, Int> {
        return Dictionary()
    }
}
