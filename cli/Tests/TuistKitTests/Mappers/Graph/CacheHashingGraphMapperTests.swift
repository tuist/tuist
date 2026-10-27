import Testing
import TuistCore
import XcodeGraph
@testable import TuistKit
@testable import TuistTesting

struct CacheHashingGraphMapperTests {
    @Test func map_stores_normalized_hashing_graph_without_mutating_returned_graph() async throws {
        // Given
        let graph = Graph.test(name: "original")
        let subject = CacheHashingGraphMapper(normalizationMappers: [
            AnyGraphMapper { graph in
                var graph = graph
                graph.name = "normalized"
                return (graph, [], MapperEnvironment())
            },
        ])

        // When
        let (gotGraph, sideEffects, gotEnvironment) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then
        #expect(gotGraph.name == "original")
        #expect(sideEffects.isEmpty)
        #expect(gotEnvironment.initialGraphWithSources?.name == "normalized")
    }

    @Test func map_does_not_overwrite_existing_hashing_graph() async throws {
        // Given
        let graph = Graph.test(name: "original")
        let existingHashingGraph = Graph.test(name: "existing")
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = existingHashingGraph
        let subject = CacheHashingGraphMapper(normalizationMappers: [
            AnyGraphMapper { graph in
                var graph = graph
                graph.name = "normalized"
                return (graph, [], MapperEnvironment())
            },
        ])

        // When
        let (_, _, gotEnvironment) = try await subject.map(
            graph: graph,
            environment: environment
        )

        // Then
        #expect(gotEnvironment.initialGraphWithSources == existingHashingGraph)
    }
}
