import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockTestsGraphContentHasher: TestsGraphContentHashing {
    public init() {}

    public var contentHashesStub: ((Graph) throws -> [TargetNode: String])?
    public func contentHashes(
        graph: Graph
    ) throws -> [TargetNode : String] {
        try contentHashesStub?(graph) ?? [:]
    }
}
