import Basic
import Foundation
import TuistCore

/// A protocol that defines an interface to map dependency graphs.
protocol ProjectGeneratorGraphMapping {
    /// Given a graph, it maps it into another graph.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: Graph) throws -> Graph
}

/// A mapper that is initialized with a mapping function.
final class AnyProjectGeneratorGraphMapper: ProjectGeneratorGraphMapping {
    /// A function to map the graph.
    let mapper: (Graph) throws -> Graph

    /// Default initializer
    /// - Parameter mapper: Function to map the graph.
    init(mapper: @escaping (Graph) throws -> Graph) {
        self.mapper = mapper
    }

    func map(graph: Graph) throws -> Graph {
        try mapper(graph)
    }
}

final class ProjectGeneratorSequentialGraphMapper: ProjectGeneratorGraphMapping {
    /// List of mappers to be executed sequentially.
    private let mappers: [ProjectGeneratorGraphMapping]

    /// Default initializer
    /// - Parameter mappers: List of mappers to be executed sequentially.
    init(mappers: [ProjectGeneratorGraphMapping]) {
        self.mappers = mappers
    }

    func map(graph: Graph) throws -> Graph {
        try mappers.reduce(graph) { try $1.map(graph: $0) }
    }
}
