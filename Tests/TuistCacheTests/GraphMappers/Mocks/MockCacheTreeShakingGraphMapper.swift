import Foundation
import TuistGraph
@testable import TuistCache
@testable import TuistCore

public final class MockCacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    var invokedMapGraph = false
    var invokedMapGraphCount = 0
    var invokedMapGraphParameters: (graph: ValueGraph, Void)?
    var invokedMapGraphParametersList = [(graph: ValueGraph, Void)]()
    var stubbedMapGraphError: Error?
    var stubbedMapGraphResult: (ValueGraph, [SideEffectDescriptor])!

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
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
