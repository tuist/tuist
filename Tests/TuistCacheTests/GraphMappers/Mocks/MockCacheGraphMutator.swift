import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class MockCacheGraphMutator: CacheGraphMutating {
    var invokedMap = false
    var invokedMapCount = 0
    var invokedMapParameters: (graph: Graph, xcframeworks: [TargetNode: AbsolutePath], sources: Set<String>)?
    var invokedMapParametersList = [(graph: Graph, xcframeworks: [TargetNode: AbsolutePath], sources: Set<String>)]()
    var stubbedMapError: Error?
    var stubbedMapResult: Graph!

    func map(graph: Graph, xcframeworks: [TargetNode: AbsolutePath], sources: Set<String>) throws -> Graph {
        invokedMap = true
        invokedMapCount += 1
        invokedMapParameters = (graph, xcframeworks, sources)
        invokedMapParametersList.append((graph, xcframeworks, sources))
        if let error = stubbedMapError {
            throw error
        }
        return stubbedMapResult
    }
}
