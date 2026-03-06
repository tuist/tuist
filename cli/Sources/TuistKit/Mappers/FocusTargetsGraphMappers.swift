import Foundation
import TSCBasic
import TuistConfig
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

public enum FocusTargetsGraphMappersError: FatalError, Equatable {
    case targetsNotFound([String])
    case noTargetsFound

    public var type: ErrorType {
        switch self {
        case .targetsNotFound, .noTargetsFound:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .targetsNotFound(targets):
            return "The following targets were not found: \(targets.joined(separator: ", ")). Please, make sure they exist."
        case .noTargetsFound:
            return "No targets were found. Ensure that the query is valid and matches targets in the graph."
        }
    }
}

/// `FocusTargetsGraphMappers` is used to filter out some targets and their dependencies and tests targets.
public struct FocusTargetsGraphMappers: GraphMapping {
    /// When specified, if includedTargets is empty it will automatically include all targets in the test plan.
    public let testPlan: String?
    /// The targets to be kept as non prunable with their respective dependencies and tests targets.
    public let includedTargets: Set<TargetQuery>
    public let excludedTargets: Set<TargetQuery>
    /// When true and no explicit filters are provided, automatically focuses on test targets and their dependencies.
    public let isTestingContext: Bool

    public init(
        testPlan: String? = nil,
        includedTargets: Set<TargetQuery>,
        excludedTargets: Set<TargetQuery> = [],
        isTestingContext: Bool = false
    ) {
        self.testPlan = testPlan
        self.includedTargets = includedTargets
        self.excludedTargets = excludedTargets
        self.isTestingContext = isTestingContext
    }

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let graphTraverser = GraphTraverser(graph: graph)
        var graph = graph

        let hasExplicitFilters = !includedTargets.isEmpty || !excludedTargets.isEmpty || testPlan != nil
        let sourceTargets: Set<GraphTarget>

        if isTestingContext, !hasExplicitFilters {
            let testTargets = graphTraverser.allTargets().filter { $0.target.product.testsBundle }
            sourceTargets = testTargets
        } else {
            let userSpecifiedSourceTargets = graphTraverser.filterIncludedTargets(
                basedOn: graphTraverser.allTargets(),
                testPlan: testPlan,
                includedTargets: includedTargets,
                excludedTargets: excludedTargets,
                excludingExternalTargets: true
            )

            let includedTargetNames: [String] = includedTargets.compactMap {
                guard case let .named(name) = $0 else { return nil }
                return name
            }
            let unavailableIncludedTargets = Set(includedTargetNames)
                .subtracting(userSpecifiedSourceTargets.map(\.target.name))
            if !unavailableIncludedTargets.isEmpty {
                throw FocusTargetsGraphMappersError.targetsNotFound(Array(unavailableIncludedTargets))
            }

            if !includedTargets.isEmpty || !excludedTargets.isEmpty, userSpecifiedSourceTargets.isEmpty {
                throw FocusTargetsGraphMappersError.noTargetsFound
            }

            sourceTargets = userSpecifiedSourceTargets
        }

        let filteredTargets = Set(try topologicalSort(
            Array(sourceTargets),
            successors: { Array(graphTraverser.directTargetDependencies(path: $0.path, name: $0.target.name)).map(\.graphTarget) }
        ))

        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.targets = project.targets.mapValues { target in
                var target = target
                if !filteredTargets.contains(GraphTarget(path: project.path, target: target, project: project)) {
                    target.metadata.tags.formUnion(["tuist:prunable"])
                }
                return target
            }

            return project
        }

        return (graph, [], environment)
    }
}
