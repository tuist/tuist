import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public init() {}

    public var contentHashesStub: ((Graph, (GraphTarget) -> Bool, [String]) throws -> [GraphTarget: String])?
    public func contentHashes(
        for graph: Graph,
        filter: (GraphTarget) -> Bool,
        additionalStrings: [String]
    ) throws -> [GraphTarget: String] {
        try contentHashesStub?(graph, filter, additionalStrings) ?? [:]
    }
}
