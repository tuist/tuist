import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public init() {}

    public var contentHashesStub: ((TuistCore.Graph, (TargetNode) -> Bool, [String]) throws -> [TargetNode: String])?
    public func contentHashes(
        for graph: TuistCore.Graph,
        filter: (TargetNode) -> Bool,
        additionalStrings: [String]
    ) throws -> [TargetNode: String] {
        try contentHashesStub?(graph, filter, additionalStrings) ?? [:]
    }
}
