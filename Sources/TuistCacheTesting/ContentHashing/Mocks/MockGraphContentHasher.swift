import Foundation
import TuistCore
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {

    var invokedContentHashes = false
    var invokedContentHashesCount = 0
    var invokedContentHashesParameters: (graphTraverser: GraphTraversing, cacheOutputType: CacheOutputType)?
    var invokedContentHashesParametersList = [(graphTraverser: GraphTraversing, cacheOutputType: CacheOutputType)]()
    var stubbedContentHashesError: Error?
    var stubbedContentHashesResult: [ValueGraphTarget: String]! = [:]

    func contentHashes(graphTraverser: GraphTraversing, cacheOutputType: CacheOutputType) throws -> [ValueGraphTarget: String] {
        invokedContentHashes = true
        invokedContentHashesCount += 1
        invokedContentHashesParameters = (graphTraverser, cacheOutputType)
        invokedContentHashesParametersList.append((graphTraverser, cacheOutputType))
        if let error = stubbedContentHashesError {
            throw error
        }
        return stubbedContentHashesResult
    }
}
