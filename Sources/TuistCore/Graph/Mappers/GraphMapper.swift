import Basic
import Foundation

/// A protocol that defines an interface to map dependency graphs.
public protocol GraphMapping {
    /// Given a graph, it maps it into another graph.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: Graph) throws -> Graph
}

/// A mapper that is initialized with a mapping function.
public final class AnyGraphMapper: GraphMapping {
    /// A function to map the graph.
    let mapper: (Graph) throws -> Graph

    /// Default initializer
    /// - Parameter mapper: Function to map the graph.
    public init(mapper: @escaping (Graph) throws -> Graph) {
        self.mapper = mapper
    }

    public func map(graph: Graph) throws -> Graph {
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

    public func map(graph: Graph) throws -> Graph {
        try mappers.reduce(graph) { try $1.map(graph: $0) }
    }
}
