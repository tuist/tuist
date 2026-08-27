import Foundation
import TuistConfig
import TuistCore
import XcodeGraph

/// Validates the targets a command was asked to focus on without touching the graph.
///
/// `FocusTargetsGraphMappers` is what normally rejects a target that is not in the graph, but
/// `cacheOptions.keepSourceTargets` deliberately keeps every target in the generated project and so
/// runs no focus mapper. This restores the same validation for that path, so a misspelled target
/// fails the command instead of silently generating the whole workspace.
struct ValidateIncludedTargetsGraphMapper: GraphMapping {
    let includedTargets: Set<TargetQuery>

    func map(graph: Graph, environment: MapperEnvironment) throws -> (
        Graph, [SideEffectDescriptor], MapperEnvironment
    ) {
        guard !includedTargets.isEmpty else { return (graph, [], environment) }

        let graphTraverser = GraphTraverser(graph: graph)
        let matchedTargets = graphTraverser.filterIncludedTargets(
            basedOn: graphTraverser.allTargets(),
            testPlan: nil,
            includedTargets: includedTargets,
            excludedTargets: []
        )

        let includedTargetNames: [String] = includedTargets.compactMap {
            guard case let .named(name) = $0 else { return nil }
            return name
        }
        let unavailableIncludedTargets = Set(includedTargetNames)
            .subtracting(matchedTargets.map(\.target.name))
        if !unavailableIncludedTargets.isEmpty {
            throw FocusTargetsGraphMappersError.targetsNotFound(Array(unavailableIncludedTargets))
        }

        if matchedTargets.isEmpty {
            throw FocusTargetsGraphMappersError.noTargetsFound
        }

        return (graph, [], environment)
    }
}
