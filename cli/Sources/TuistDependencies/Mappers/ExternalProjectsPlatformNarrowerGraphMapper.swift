import Foundation
import Logging
import TuistCore
import XcodeGraph

/// When Swift Packages don't declare the platforms that they support, the Swift Package Manager defaults the value
/// to 'support all the platforms'. This default behaviour is inherited into the Xcode projects that we generate off the packages
/// and that causes compilation issues. Xcode must resolve this issue at build-time by cascading the platform requirements
/// down from nodes in the graph that are closer to the root. This is a behaviour that we need to copy over to Tuist. In our case
/// the logic is executed at generation time.
public struct ExternalProjectsPlatformNarrowerGraphMapper: GraphMapping { // swiftlint:disable:this type_name
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [TuistCore.SideEffectDescriptor], MapperEnvironment) {
        Logger.current.debug("Transforming graph \(graph.name): Aligning external target platforms with locals'")

        // If the project has no external dependencies we skip this.
        if graph.projects.values.first(
            where: {
                switch $0.type {
                case .external:
                    return true
                case .local:
                    return false
                }
            }
        ) == nil {
            return (graph, [], environment)
        }

        var graph = graph
        let graphTraverser = GraphTraverser(graph: graph)
        var externalTargetSupportedDestinations = graphTraverser.externalTargetSupportedDestinations()
        let testDestinations = LocalPackageTestDestinationResolver().resolve(
            graphTraverser: graphTraverser,
            productionDestinations: externalTargetSupportedDestinations,
            graphBeforeTestFocus: environment.graphBeforeTestFocus
        )
        let narrowedTests = testDestinations.compactMap { test, destinations -> GraphTarget? in
            guard !destinations.isEmpty else { return nil }
            var target = test.target
            target.destinations = destinations
            return GraphTarget(path: test.path, target: target, project: test.project)
        }
        if !narrowedTests.isEmpty {
            // Only tests with inferred platforms may extend the production traversal. Orphan
            // tests must not propagate their broad declared destinations back into runtime targets.
            // Preserve production destinations when tests connect dependencies with disjoint platforms.
            let productionDestinations = externalTargetSupportedDestinations
            externalTargetSupportedDestinations = graphTraverser.externalTargetSupportedDestinations(
                including: Set(narrowedTests)
            ).merging(productionDestinations) { _, production in production }
        }
        externalTargetSupportedDestinations.merge(testDestinations) { _, testDestinations in testDestinations }

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { _, target in
                let mappedTarget = mapTarget(
                    target: target,
                    project: project,
                    externalTargetSupportedDestinations: externalTargetSupportedDestinations
                )
                return (mappedTarget.name, mappedTarget)
            })
            return (projectPath, project)
        })
        removeDependenciesExcludedByNarrowedPlatforms(graph: &graph)

        return (graph, [], environment)
    }

    /// Drops dependencies of external targets whose platform condition matches none of the target's narrowed destinations.
    /// For example, a macro-only helper that links SwiftPM's prebuilt swift-syntax on macOS keeps its source swift-syntax
    /// dependency only for the other platforms. Once the helper is narrowed to macOS, that edge can never apply, and keeping
    /// it would pair a macOS-only target with a dependency narrowed to other platforms.
    ///
    /// The target's own dependencies lose it too. Binary-cache hashing hashes a target's dependencies after the targets its
    /// graph edges reach, so a dependency left without an edge has no hash yet when the target is hashed.
    private func removeDependenciesExcludedByNarrowedPlatforms(graph: inout Graph) {
        for (edge, condition) in graph.dependencyConditions {
            guard case let .target(name, path, _) = edge.from,
                  let project = graph.projects[path],
                  case .external = project.type,
                  let target = project.targets[name]
            else { continue }
            // Targets narrowed to no destinations are pruned, so their edges are left for pruning to handle.
            let platformFilters = Set(target.destinations.map(\.platformFilter))
            guard !platformFilters.isEmpty, platformFilters.isDisjoint(with: condition.platformFilters) else { continue }
            graph.dependencies[edge.from]?.remove(edge.to)
            graph.dependencyConditions.removeValue(forKey: edge)
            guard case let .target(dependencyName, dependencyPath, _) = edge.to else { continue }
            graph.projects[path]?.targets[name]?.dependencies.removeAll { dependency in
                let targetName: String
                switch dependency {
                case let .target(name, _, _) where dependencyPath == path:
                    targetName = name
                case let .project(name, projectPath, _, _) where projectPath == dependencyPath:
                    targetName = name
                default:
                    return false
                }
                return targetName == dependencyName
                    && dependency.condition.map { platformFilters.isDisjoint(with: $0.platformFilters) } == true
            }
        }
    }

    private func mapTarget(
        target: Target,
        project: Project,
        externalTargetSupportedDestinations: [GraphTarget: Set<Destination>]
    ) -> Target {
        var target = target
        let graphTarget = GraphTarget(path: project.path, target: target, project: project)
        guard case .external = project.type else { return target }

        let targetFilteredDestinations = externalTargetSupportedDestinations[graphTarget]

        if let targetFilteredDestinations {
            target.destinations = targetFilteredDestinations
            if target.destinations.isEmpty {
                target.metadata.tags = Set(Array(target.metadata.tags) + ["tuist:prunable"])
            }

            let supportedPlatforms = targetFilteredDestinations.platforms
            target.deploymentTargets = .init(
                iOS: supportedPlatforms.contains(.iOS) ? target.deploymentTargets.iOS : nil,
                macOS: supportedPlatforms.contains(.macOS) ? target.deploymentTargets.macOS : nil,
                watchOS: supportedPlatforms.contains(.watchOS) ? target.deploymentTargets.watchOS : nil,
                tvOS: supportedPlatforms.contains(.tvOS) ? target.deploymentTargets.tvOS : nil,
                visionOS: supportedPlatforms.contains(.visionOS) ? target.deploymentTargets.visionOS : nil
            )
        }
        return target
    }
}
