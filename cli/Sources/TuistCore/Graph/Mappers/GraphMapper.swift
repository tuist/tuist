import Foundation
import TuistLogging
import XcodeGraph

/// A protocol that defines an interface to map dependency graphs.
public protocol GraphMapping {
    /// Given a value graph, it maps it into another value graph.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: Graph, environment: MapperEnvironment) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment)
}

/// A mapper that is initialized with a mapping function.
public struct AnyGraphMapper: GraphMapping {
    /// A function to map the graph.
    let mapper: (Graph) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment)

    /// Default initializer
    /// - Parameter mapper: Function to map the graph.
    public init(mapper: @escaping (Graph) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment)) {
        self.mapper = mapper
    }

    public func map(graph: Graph, environment _: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        try mapper(graph)
    }
}

public struct SequentialGraphMapper: GraphMapping {
    /// List of mappers to be executed sequentially.
    private let mappers: [GraphMapping]

    /// Default initializer
    /// - Parameter mappers: List of mappers to be executed sequentially.
    public init(_ mappers: [GraphMapping]) {
        self.mappers = mappers
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph
        var sideEffects = [SideEffectDescriptor]()
        var environment = environment
        for mapper in mappers {
            // Timed here rather than in each mapper so every mapper is attributable in the session log, including
            // the ones that log nothing of their own. Nested sequences (the cache-hash normalization pass) report
            // their own mappers first, followed by the total for the mapper that wraps them.
            let name = String(describing: type(of: mapper))
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let (mappedGraph, newSideEffects, newEnvironment) = try await mapper.map(graph: graph, environment: environment)
            let duration = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
            Logger.current.debug("Mapper \(name) finished in \(String(format: "%.3f", duration))s")
            sideEffects.append(contentsOf: newSideEffects)
            graph = mappedGraph
            environment = newEnvironment
        }
        return (graph, sideEffects, environment)
    }
}
