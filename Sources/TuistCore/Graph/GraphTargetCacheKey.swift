import Foundation
import TuistGraph

final class GraphTargetCacheKey: NSObject {
    // MARK: - Properties

    let target: GraphTarget

    // MARK: - Initialisers

    init(_ target: GraphTarget) {
        self.target = target
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Self else {
            return false
        }

        return target == other.target
    }

    override var hash: Int {
        target.hashValue
    }
}
