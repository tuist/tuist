import Foundation
import TSCBasic

/// A protocol that defines an interface to map dependency graphs.
public protocol GraphMapping {
    /// Given a graph, it maps it into another graph.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor])

    /// Given a value graph, it maps it into another value graph.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])
}

public extension GraphMapping {
    func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        return (graph, [])
    }
}

/// A mapper that is initialized with a mapping function.
public final class AnyGraphMapper: GraphMapping {
    /// A function to map the graph.
    let mapper: (Graph) throws -> (Graph, [SideEffectDescriptor])

    /// Default initializer
    /// - Parameter mapper: Function to map the graph.
    public init(mapper: @escaping (Graph) throws -> (Graph, [SideEffectDescriptor])) {
        self.mapper = mapper
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
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

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        try mappers.reduce((graph, [SideEffectDescriptor]())) { input, mapper in
            let graph = input.0
            var sideEffects = input.1
            let (mappedGraph, newSideEffects) = try mapper.map(graph: graph)
            sideEffects.append(contentsOf: newSideEffects)
            return (mappedGraph, sideEffects)
        }
    }
}
