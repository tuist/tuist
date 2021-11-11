import Foundation
import TuistGraph
@testable import TuistCache
@testable import TuistCore

public final class MockCacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    var invokedMapGraph = false
    var invokedMapGraphCount = 0
    var invokedMapGraphParameters: (graph: Graph, Void)?
    var invokedMapGraphParametersList = [(graph: Graph, Void)]()
    var stubbedMapGraphError: Error?
    var stubbedMapGraphResult: (Graph, [SideEffectDescriptor])!

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        invokedMapGraph = true
        invokedMapGraphCount += 1
        invokedMapGraphParameters = (graph, ())
        invokedMapGraphParametersList.append((graph, ()))
        if let error = stubbedMapGraphError {
            throw error
        }
        return stubbedMapGraphResult
    }
}
