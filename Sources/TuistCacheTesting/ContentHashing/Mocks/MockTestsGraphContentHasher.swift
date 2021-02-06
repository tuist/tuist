import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockTestsGraphContentHasher: TestsGraphContentHashing {
    public init() {}

    public var contentHashesStub: ((GraphTraversing) throws -> [ValueGraphTarget: String])?
    public func contentHashes(
        graphTraverser: GraphTraversing
    ) throws -> [ValueGraphTarget : String] {
        try contentHashesStub?(graphTraverser) ?? [:]
    }
}
