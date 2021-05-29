import Foundation
import TSCBasic
import TuistGraph

/// A protocol that defines an interface to map dependency graphs.
public protocol GraphMapping {
    /// Given a value graph, it maps it into another value graph.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])
}

/// A mapper that is initialized with a mapping function.
public final class AnyGraphMapper: GraphMapping {
    /// A function to map the graph.
    let mapper: (ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])

    /// Default initializer
    /// - Parameter mapper: Function to map the graph.
    public init(mapper: @escaping (ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])) {
        self.mapper = mapper
    }

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        try mapper(graph)
    }
}

public final class SequentialGraphMapper: GraphMapping {
    /// List of mappers to be executed sequentially.
    private let mappers: [GraphMapping]

    /// Default initializer
    /// - Parameter mappers: List of mappers to be executed sequentially.
    public init(_ mappers: [GraphMapping]) {
        self.mappers = mappers
    }

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        try mappers.reduce((graph, [SideEffectDescriptor]())) { input, mapper in
            let graph = input.0
            var sideEffects = input.1
            let (mappedGraph, newSideEffects) = try mapper.map(graph: graph)
            sideEffects.append(contentsOf: newSideEffects)
            return (mappedGraph, sideEffects)
        }
    }
}
