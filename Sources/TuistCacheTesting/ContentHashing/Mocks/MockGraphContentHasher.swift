import Foundation
import TuistCore
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public init() {}

    public var contentHashesStub: ((TuistCore.Graph, (TargetNode) -> Bool) throws -> [TargetNode: String])?
    public func contentHashes(for graph: TuistCore.Graph, filter: (TargetNode) -> Bool) throws -> [TargetNode: String] {
        try contentHashesStub?(graph, filter) ?? [:]
    }

    public func contentHashes(for graph: Graph) throws -> [TargetNode : String] {
        try contentHashesStub?(graph, { _ in true }) ?? [:]
    }
}
