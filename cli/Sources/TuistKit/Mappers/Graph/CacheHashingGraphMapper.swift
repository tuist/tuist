import TuistAlert
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
                // The normalization pass exists only to derive cache hashes, so its alerts are discarded the
                // same way its side effects and environment are. They describe the graph before focusing and
                // tree-shaking, so surfacing them would report targets that never reach the generated project
                // and would restate, with a different target count, what the real mapping pass reports.
                let (hashingGraph, _, _) = try await AlertController.$current.withValue(AlertController()) {
                    try await normalizationMapper.map(
                        graph: graph,
                        environment: environment
                    )
                }
                environment.initialGraphWithSources = hashingGraph
            } else {
                environment.initialGraphWithSources = graph
            }
        }
        return (graph, [], environment)
    }
    // swiftlint:enable large_tuple
}
