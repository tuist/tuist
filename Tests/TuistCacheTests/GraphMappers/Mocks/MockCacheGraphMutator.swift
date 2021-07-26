import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class MockCacheGraphMutator: CacheGraphMutating {
    var invokedMap = false
    var invokedMapCount = 0
    var invokedMapParameters: (graph: Graph, precompiledFrameworks: [GraphTarget: AbsolutePath], sources: Set<String>)?
    var invokedMapParametersList = [(graph: Graph, precompiledFrameworks: [GraphTarget: AbsolutePath], sources: Set<String>)]()
    var stubbedMapError: Error?
    var stubbedMapResult: Graph!

    func map(graph: Graph, precompiledArtifacts: [GraphTarget: AbsolutePath], sources: Set<String>) throws -> Graph {
        invokedMap = true
        invokedMapCount += 1
        invokedMapParameters = (graph, precompiledArtifacts, sources)
        invokedMapParametersList.append((graph, precompiledArtifacts, sources))
        if let error = stubbedMapError {
            throw error
        }
        return stubbedMapResult
    }
}
