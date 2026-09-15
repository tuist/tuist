import Foundation
import Logging
import TuistCore
import XcodeGraph

/// External dependencies might contain targets that are only relevant in development, but that
/// that are not necessary when the dependencies are consumed downstream by Tuist projects.
/// This graph mappers detects and prunes those targets.
public struct PruneOrphanExternalTargetsGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: XcodeGraph.Graph,
        environment: MapperEnvironment
    ) async throws -> (XcodeGraph.Graph, [TuistCore.SideEffectDescriptor], MapperEnvironment) {
        Logger.current
            .debug("Transforming graph \(graph.name): Tree-shaking orphan external targets (e.g. test targets)")

        let graphTraverser = GraphTraverser(graph: graph)
        let testDestinations = LocalPackageTestDestinationResolver().resolve(
            graphTraverser: graphTraverser,
            productionDestinations: graphTraverser.externalTargetSupportedDestinations(),
            graphBeforeTestFocus: environment.graphBeforeTestFocus
        )
        let localPackageTests = Set(testDestinations.compactMap { test, destinations -> GraphTarget? in
            guard !destinations.isEmpty else { return nil }
            var target = test.target
            target.destinations = destinations
            return GraphTarget(path: test.path, target: target, project: test.project)
        })
        let localPackageTestClosure: Set<GraphTarget>
        if localPackageTests.isEmpty {
            localPackageTestClosure = []
        } else {
            localPackageTestClosure = Set(
                graphTraverser.externalTargetSupportedDestinations(including: localPackageTests)
                    .filter { !$0.value.isEmpty }
                    .map(\.key)
            )
        }
        let orphanExternalTargets = graphTraverser.allOrphanExternalTargets().subtracting(localPackageTestClosure)

        var graph = graph

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.compactMap { _, target -> (String, Target)? in
                let project = graph.projects[projectPath]!
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)
                var target = target
                if testDestinations[graphTarget]?.isEmpty == false {
                    return (target.name, target)
                }
                if orphanExternalTargets.contains(graphTarget) || target.destinations.isEmpty {
                    target.metadata.tags.formUnion(["tuist:prunable"])
                }
                return (target.name, target)
            })
            return (projectPath, project)
        })

        return (graph, [], environment)
    }
}
