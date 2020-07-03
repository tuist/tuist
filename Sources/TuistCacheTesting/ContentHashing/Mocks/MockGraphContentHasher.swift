import Foundation
import TuistCore
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public init() {}

    public var invokedContentHashes = false
    public var invokedContentHashesCount = 0
    public var invokedContentHashesParameters: (graph: TuistCore.Graph, Void)?
    public var invokedContentHashesParametersList = [(graph: TuistCore.Graph, Void)]()
    public var stubbedContentHashesError: Error?
    public var contentHashesStub: [TargetNode: String]! = [:]

    public func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String] {
        invokedContentHashes = true
        invokedContentHashesCount += 1
        invokedContentHashesParameters = (graph, ())
        invokedContentHashesParametersList.append((graph, ()))
        if let error = stubbedContentHashesError {
            throw error
        }
        return contentHashesStub
    }
}
