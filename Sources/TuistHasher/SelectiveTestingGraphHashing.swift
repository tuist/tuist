import Foundation
import Mockable
import XcodeGraph

@Mockable
public protocol SelectiveTestingGraphHashing {
    /// - Parameters:
    /// - graph: Graph to hash.
    /// - additionalStrings: Additional strings that should be added to each target hash.
    /// - Returns: A dictionary where key is a `GraphTarget` and a value is its hash
    func hash(
        graph: Graph,
        additionalStrings: [String]
    ) async throws -> [GraphTarget: String]
}
