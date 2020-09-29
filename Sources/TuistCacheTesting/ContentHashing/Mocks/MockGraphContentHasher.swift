import Foundation
import TuistCore
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public init() {}

    public var invokedContentHashes = false
    public var invokedContentHashesCount = 0
    public var invokedContentHashesParameters: (graph: TuistCore.Graph, artifactType: ArtifactType)?
    public var invokedContentHashesParametersList = [(graph: TuistCore.Graph, artifactType: ArtifactType)]()
    public var stubbedContentHashesError: Error?
    public var contentHashesStub: [TargetNode: String]! = [:]

    public func contentHashes(for graph: TuistCore.Graph, artifactType: ArtifactType) throws -> [TargetNode: String] {
        invokedContentHashes = true
        invokedContentHashesCount += 1
        invokedContentHashesParameters = (graph, artifactType)
        invokedContentHashesParametersList.append((graph, artifactType))
        if let error = stubbedContentHashesError {
            throw error
        }
        return contentHashesStub
    }
}
