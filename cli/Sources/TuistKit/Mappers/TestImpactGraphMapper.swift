import Foundation
import Path
import TuistConfig
import TuistCore
import XcodeGraph

/// Applies coverage-based test selection to the graph, right after selective testing tagged the test
/// targets whose hash already passed, and before they are pruned.
///
/// It asks `TestImpactSelector.current` about the test targets in scope that hashing left. Modules none
/// of whose tests was selected are tagged prunable like hash hits, so they aren't built. When selection
/// says every test runs (the default branch, or a fallback that makes the commit a baseline), the
/// targets hashing tagged are kept. Without a selector, the graph is unchanged.
struct TestImpactGraphMapper: GraphMapping {
    private static let prunableTag = "tuist:prunable"

    let testPlan: String?
    let schemeName: String?
    let includedTargets: Set<TargetQuery>
    let excludedTargets: Set<TargetQuery>

    // swiftlint:disable large_tuple
    func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        // swiftlint:enable large_tuple
        guard let selector = TestImpactSelector.current else { return (graph, [], environment) }

        let inScope = testTargetsInScope(graph: graph)
        let left = inScope.filter { !$0.target.metadata.tags.contains(Self.prunableTag) }
        let invocation = await selector.invocation
        let affectedModules = TestImpactAffectedModules(graph: graph)
        let decision = await selector.decide(
            modules: Set(left.map(\.target.name)).sorted(),
            platform: (invocation.platform ?? Self.sharedPlatform(of: left.isEmpty ? inScope : left))?.rawValue,
            affectedModules: { affectedModules.affectedModules(path: $0) }
        )

        switch decision {
        case .unchanged:
            return (graph, [], environment)
        case let .prune(modules):
            let pruned = Set(left.filter { modules.contains($0.target.name) }.map(Self.reference))
            return (graph.mappingTargets { reference, target in
                if pruned.contains(reference) { target.metadata.tags.insert(Self.prunableTag) }
            }, [], environment)
        case .runAll:
            // `initialGraph` is the graph before hashing tagged anything, so a target prunable there
            // was tagged for another reason (such as `--skip-ui-tests`) and stays so.
            let prunableBefore = Set(
                (environment.initialGraph.map(GraphTraverser.init)?.allTargets() ?? [])
                    .filter { $0.target.metadata.tags.contains(Self.prunableTag) }
                    .map(Self.reference)
            )
            let kept = Set(
                inScope
                    .filter { $0.target.metadata.tags.contains(Self.prunableTag) }
                    .map(Self.reference)
            ).subtracting(prunableBefore)
            var environment = environment
            for target in kept {
                environment.targetTestCacheItems[target.projectPath]?[target.name] = nil
            }
            return (graph.mappingTargets { reference, target in
                if kept.contains(reference) { target.metadata.tags.remove(Self.prunableTag) }
            }, [], environment)
        }
    }

    /// The unit and UI test targets the invocation tests: the scheme's when one is named, narrowed by
    /// the test plan and the requested and skipped targets, as selective testing narrows them.
    private func testTargetsInScope(graph: Graph) -> Set<GraphTarget> {
        let graphTraverser = GraphTraverser(graph: graph)
        var candidates = graphTraverser.allTargets().filter {
            $0.target.product == .unitTests || $0.target.product == .uiTests
        }
        if let schemeName, let testAction = graphTraverser.schemes().first(where: { $0.name == schemeName })?.testAction {
            let references = Set(
                testAction.targets.map(\.target) + (testAction.testPlans ?? []).flatMap { $0.testTargets.map(\.target) }
            )
            candidates = candidates.filter { references.contains(Self.reference($0)) }
        }
        return graphTraverser.filterIncludedTargets(
            basedOn: candidates,
            testPlan: testPlan,
            includedTargets: includedTargets,
            excludedTargets: excludedTargets
        )
    }

    private static func reference(_ target: GraphTarget) -> TargetReference {
        TargetReference(projectPath: target.path, name: target.target.name)
    }

    /// The one platform every target supports, nil when they don't share exactly one.
    private static func sharedPlatform(of targets: Set<GraphTarget>) -> XcodeGraph.Platform? {
        guard let first = targets.first else { return nil }
        let shared = targets.dropFirst().reduce(first.target.supportedPlatforms) { $0.intersection($1.target.supportedPlatforms) }
        return shared.count == 1 ? shared.first : nil
    }
}

extension Graph {
    fileprivate func mappingTargets(_ transform: (TargetReference, inout Target) -> Void) -> Graph {
        var graph = self
        graph.projects = projects.mapValues { project in
            var project = project
            project.targets = project.targets.mapValues { target in
                var target = target
                transform(TargetReference(projectPath: project.path, name: target.name), &target)
                return target
            }
            return project
        }
        return graph
    }
}
