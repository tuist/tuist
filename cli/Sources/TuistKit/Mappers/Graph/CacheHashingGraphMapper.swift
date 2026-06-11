import TuistCore
import XcodeGraph

/// Preserves the graph that module-cache hashes should be derived from.
///
/// Some workflows focus or tree-shake the graph before binary-cache replacement runs. That focused graph is
/// the right graph to generate, but cache keys need to stay aligned with cache warm/hash, which operate on
/// the normalized source graph.
public struct CacheHashingGraphMapper: GraphMapping {
    private let normalizationMapper: GraphMapping?

    public init(normalizationMappers: [GraphMapping] = []) {
        normalizationMapper = normalizationMappers.isEmpty ? nil : SequentialGraphMapper(normalizationMappers)
    }

    // swiftlint:disable large_tuple
    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var environment = environment
        if environment.initialGraphWithSources == nil {
            if let normalizationMapper {
                let (hashingGraph, _, _) = try await normalizationMapper.map(
                    graph: graph,
                    environment: environment
                )
                environment.initialGraphWithSources = hashingGraph
            } else {
                environment.initialGraphWithSources = graph
            }
        }
        return (graph, [], environment)
    }
    // swiftlint:enable large_tuple
}
