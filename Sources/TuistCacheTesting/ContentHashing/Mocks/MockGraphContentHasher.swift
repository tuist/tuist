import Foundation
import TuistCore
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public var contentHashesStub: [TargetNode: String] = [:]

    public init() {}

    public func contentHashes(for _: Graphing) throws -> [TargetNode: String] {
        contentHashesStub
    }
}
