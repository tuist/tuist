import Foundation
import TuistGraph
@testable import TuistCache
@testable import TuistCore

public final class MockCacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    var invokedMapGraphGraph = false
    var invokedMapGraphGraphCount = 0
    var invokedMapGraphGraphParameters: (graph: Graph, Void)?
    var invokedMapGraphGraphParametersList = [(graph: Graph, Void)]()
    var stubbedMapGraphGraphError: Error?
    var stubbedMapGraphGraphResult: (Graph, [SideEffectDescriptor])!

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        invokedMapGraphGraph = true
        invokedMapGraphGraphCount += 1
        invokedMapGraphGraphParameters = (graph, ())
        invokedMapGraphGraphParametersList.append((graph, ()))
        if let error = stubbedMapGraphGraphError {
            throw error
        }
        return stubbedMapGraphGraphResult
    }

    var invokedMapGraphValueGraph = false
    var invokedMapGraphValueGraphCount = 0
    var invokedMapGraphValueGraphParameters: (graph: ValueGraph, Void)?
    var invokedMapGraphValueGraphParametersList = [(graph: ValueGraph, Void)]()
    var stubbedMapGraphValueGraphError: Error?
    var stubbedMapGraphValueGraphResult: (ValueGraph, [SideEffectDescriptor])!

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        invokedMapGraphValueGraph = true
        invokedMapGraphValueGraphCount += 1
        invokedMapGraphValueGraphParameters = (graph, ())
        invokedMapGraphValueGraphParametersList.append((graph, ()))
        if let error = stubbedMapGraphValueGraphError {
            throw error
        }
        return stubbedMapGraphValueGraphResult
    }
}
