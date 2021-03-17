import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class MockCacheGraphMutator: CacheGraphMutating {
    var invokedMapGraph = false
    var invokedMapGraphCount = 0
    var invokedMapGraphParameters: (graph: Graph, precompiledFrameworks: [TargetNode: AbsolutePath], sources: Set<String>)?
    var invokedMapGraphParametersList = [(graph: Graph, precompiledFrameworks: [TargetNode: AbsolutePath], sources: Set<String>)]()
    var stubbedMapGraphError: Error?
    var stubbedMapGraphResult: Graph!

    func map(graph: Graph, precompiledFrameworks: [TargetNode: AbsolutePath], sources: Set<String>) throws -> Graph {
        invokedMapGraph = true
        invokedMapGraphCount += 1
        invokedMapGraphParameters = (graph, precompiledFrameworks, sources)
        invokedMapGraphParametersList.append((graph, precompiledFrameworks, sources))
        if let error = stubbedMapGraphError {
            throw error
        }
        return stubbedMapGraphResult
    }

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
