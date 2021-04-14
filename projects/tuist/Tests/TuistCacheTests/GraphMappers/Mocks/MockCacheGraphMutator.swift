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
    var invokedMapParameters: (graph: ValueGraph, precompiledFrameworks: [ValueGraphTarget: AbsolutePath], sources: Set<String>)?
    var invokedMapParametersList = [(graph: ValueGraph, precompiledFrameworks: [ValueGraphTarget: AbsolutePath], sources: Set<String>)]()
    var stubbedMapError: Error?
    var stubbedMapResult: ValueGraph!

    func map(graph: ValueGraph, precompiledFrameworks: [ValueGraphTarget: AbsolutePath], sources: Set<String>) throws -> ValueGraph {
        invokedMap = true
        invokedMapCount += 1
        invokedMapParameters = (graph, precompiledFrameworks, sources)
        invokedMapParametersList.append((graph, precompiledFrameworks, sources))
        if let error = stubbedMapError {
            throw error
        }
        return stubbedMapResult
    }
}
