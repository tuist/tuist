import Testing
import TuistAlert
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

    @Test(.withScopedAlertController())
    func map_discards_alerts_raised_by_the_normalization_mappers() async throws {
        // Given: the normalization graph is only used to derive cache hashes, and it is the graph before
        // focusing and tree-shaking. Alerts about it would name targets the generated project never contains.
        let subject = CacheHashingGraphMapper(normalizationMappers: [
            AnyGraphMapper { graph in
                AlertController.current.warning(.alert("A warning about the pre-focus graph"))
                return (graph, [], MapperEnvironment())
            },
        ])

        // When
        _ = try await subject.map(graph: Graph.test(), environment: MapperEnvironment())

        // Then
        #expect(AlertController.current.warnings().isEmpty)
    }
}
