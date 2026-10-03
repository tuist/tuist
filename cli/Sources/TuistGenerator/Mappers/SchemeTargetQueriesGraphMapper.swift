import Foundation
import Logging
import TuistAlert
import TuistCore
import XcodeGraph

/// A mapper that resolves the target queries declared by the build and test actions of the schemes.
///
/// Queries are resolved against the targets of every project of the graph, which is why the resolution happens here
/// and not while loading the manifests: a workspace scheme can match targets that live in projects that are not known
/// yet at that point.
public struct SchemeTargetQueriesGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let schemes = graph.workspace.schemes + graph.projects.values.flatMap(\.schemes)
        guard schemes.contains(where: Self.declaresTargetQueries) else {
            return (graph, [], environment)
        }

        Logger.current.debug("Transforming graph \(graph.name): Resolving the target queries of the schemes")

        let candidates: [Candidate] = graph.projects.values
            .flatMap { project in
                project.targets.values.map { target in
                    Candidate(
                        reference: TargetReference(projectPath: project.path, name: target.name),
                        target: target
                    )
                }
            }
            .sorted { $0.reference.name < $1.reference.name }

        var graph = graph
        var workspace = graph.workspace
        workspace.schemes = workspace.schemes.map { resolve(scheme: $0, candidates: candidates) }
        graph.workspace = workspace
        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.schemes = project.schemes.map { resolve(scheme: $0, candidates: candidates) }
            return project
        }

        return (graph, [], environment)
    }

    // MARK: - Helpers

    private struct Candidate {
        let reference: TargetReference
        let target: Target
    }

    private static func declaresTargetQueries(_ scheme: Scheme) -> Bool {
        !(scheme.buildAction?.targetQueries.isEmpty ?? true) || !(scheme.testAction?.targetQueries.isEmpty ?? true)
    }

    private func resolve(scheme: Scheme, candidates: [Candidate]) -> Scheme {
        var scheme = scheme

        if var buildAction = scheme.buildAction, !buildAction.targetQueries.isEmpty {
            let matched = buildAction.targetQueries.flatMap { query in
                references(matching: query, in: candidates, scheme: scheme.name, action: "build")
            }
            buildAction.targets = uniqued(buildAction.targets + matched)
            buildAction.targetQueries = []
            scheme.buildAction = buildAction
        }

        if var testAction = scheme.testAction, !testAction.targetQueries.isEmpty {
            let matched = testAction.targetQueries.flatMap { targetQuery in
                references(
                    matching: targetQuery.query,
                    in: candidates.filter(\.target.product.testsBundle),
                    scheme: scheme.name,
                    action: "test"
                )
                .map { targetQuery.testableTarget(for: $0) }
            }
            testAction.targets = uniqued(testAction.targets + matched, by: \.target)
            testAction.targetQueries = []
            scheme.testAction = testAction
        }

        return scheme
    }

    private func references(
        matching query: TargetQuery,
        in candidates: [Candidate],
        scheme: String,
        action: String
    ) -> [TargetReference] {
        let references = candidates.filter { query.matches($0.target) }.map(\.reference)

        if references.isEmpty {
            AlertController.current.warning(.alert(
                "The \(action) action of the \(scheme) scheme declares the query \(description(of: query)), which doesn't match any target."
            ))
        }

        return references
    }

    private func description(of query: TargetQuery) -> String {
        switch query {
        case let .named(name): "named '\(name)'"
        case let .tagged(tag): "tagged 'tag:\(tag)'"
        case let .matching(pattern): "matching '\(pattern)'"
        }
    }

    private func uniqued<Element>(
        _ elements: [Element],
        by keyPath: KeyPath<Element, TargetReference>
    ) -> [Element] {
        var seen = Set<TargetReference>()
        return elements.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }

    private func uniqued(_ references: [TargetReference]) -> [TargetReference] {
        uniqued(references, by: \.self)
    }
}
