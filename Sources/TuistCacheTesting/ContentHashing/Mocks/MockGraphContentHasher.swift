import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public init() {}

    public var contentHashesStub: ((ValueGraph, (ValueGraphTarget) -> Bool, [String]) throws -> [ValueGraphTarget: String])?
    public func contentHashes(
        for graph: ValueGraph,
        filter: (ValueGraphTarget) -> Bool,
        additionalStrings: [String]
    ) throws -> [ValueGraphTarget: String] {
        try contentHashesStub?(graph, filter, additionalStrings) ?? [:]
    }
}
