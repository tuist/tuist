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
        let externalTargetSupportedDestinations = externalTargetSupportedDestinations(
            graph: graph,
            graphTraverser: graphTraverser,
            externalDependencies: environment.externalDependencies
        )

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

        return (graph, [], environment)
    }

    private func mapTarget(
        target: Target,
        project: Project,
        externalTargetSupportedDestinations: [GraphTarget: Set<Destination>]
    ) -> Target {
        var target = target
        let graphTarget = GraphTarget(path: project.path, target: target, project: project)
        if case .external = project.type,
           let targetFilteredDestinations = externalTargetSupportedDestinations[graphTarget]
        {
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

    private func externalTargetSupportedDestinations(
        graph: Graph,
        graphTraverser: GraphTraverser,
        externalDependencies: [String: [TargetDependency]]
    ) -> [GraphTarget: Set<Destination>] {
        let normalizedExternalDependencies = normalizeExternalDependencies(externalDependencies)
        let targetsWithExternalDependencies = targetsWithExternalDependencies(
            graph: graph,
            graphTraverser: graphTraverser,
            externalDependencies: normalizedExternalDependencies
        )
        var destinations: [GraphTarget: Set<Destination>] = [:]

        func traverse(target: GraphTarget, parentDestinations: Set<Destination>) {
            let dependencies = directTargetDependencies(
                for: target,
                graph: graph,
                graphTraverser: graphTraverser,
                externalDependencies: normalizedExternalDependencies
            )

            for dependencyTargetReference in dependencies {
                var destinationsToInsert: Set<Destination>?
                let dependencyTarget = dependencyTargetReference.graphTarget
                let inheritedDestinations: Set<Destination> =
                    dependencyTarget.target.product == .macro
                        ? Set<Destination>([.mac]) : parentDestinations
                if let dependencyCondition = dependencyTargetReference.condition,
                   let platformIntersection = PlatformCondition.when(
                       target.target.dependencyPlatformFilters
                   )?
                   .intersection(dependencyCondition)
                {
                    switch platformIntersection {
                    case .incompatible:
                        break
                    case let .condition(condition):
                        if let condition {
                            let allowedPlatformFilters = condition.platformFilters
                            let dependencyDestinations = inheritedDestinations.filter { destination in
                                allowedPlatformFilters.contains(destination.platformFilter)
                            }
                            destinationsToInsert = dependencyDestinations.intersection(
                                dependencyTarget.target.destinations
                            )
                        }
                    }
                } else {
                    destinationsToInsert = inheritedDestinations.intersection(
                        dependencyTarget.target.destinations
                    )
                }

                if let destinationsToInsert {
                    var existingDestinations = destinations[dependencyTarget, default: Set()]
                    let continueTraversing = !destinationsToInsert.isSubset(of: existingDestinations)
                    existingDestinations.formUnion(destinationsToInsert)
                    destinations[dependencyTarget] = existingDestinations

                    if continueTraversing {
                        traverse(
                            target: dependencyTarget,
                            parentDestinations: destinations[dependencyTarget, default: Set()]
                        )
                    }
                }
            }
        }

        for target in targetsWithExternalDependencies {
            traverse(
                target: target,
                parentDestinations: target.target.destinations
            )
        }

        return destinations
    }

    private func directTargetDependencies(
        for target: GraphTarget,
        graph: Graph,
        graphTraverser: GraphTraverser,
        externalDependencies: [String: [TargetDependency]]
    ) -> Set<GraphTargetReference> {
        var dependencies = graphTraverser.directTargetDependencies(path: target.path, name: target.target.name)
        dependencies.formUnion(
            packageProductDependencies(
                for: target,
                graph: graph,
                externalDependencies: externalDependencies
            )
        )
        return dependencies
    }

    private func packageProductDependencies(
        for target: GraphTarget,
        graph: Graph,
        externalDependencies: [String: [TargetDependency]]
    ) -> Set<GraphTargetReference> {
        let graphDependency = GraphDependency.target(name: target.target.name, path: target.path)
        guard let dependencies = graph.dependencies[graphDependency] else { return [] }

        return Set(dependencies.flatMap { dependency in
            guard case let .packageProduct(_, product, _) = dependency else { return [] }
            let dependencyCondition = graph.dependencyConditions[(graphDependency, dependency)]
            return externalTargetReferences(
                forProduct: product,
                dependencyCondition: dependencyCondition,
                externalDependencies: externalDependencies,
                graph: graph
            )
        })
    }

    private func externalTargetReferences(
        forProduct product: String,
        dependencyCondition: PlatformCondition?,
        externalDependencies: [String: [TargetDependency]],
        graph: Graph
    ) -> [GraphTargetReference] {
        guard let dependencies = externalDependencies[product] ?? externalDependencies[product.lowercased()] else { return [] }

        return dependencies.compactMap { dependency in
            guard case let .project(targetName, path, _, condition) = dependency else { return nil }
            guard let project = graph.projects[path],
                  let target = project.targets[targetName]
            else { return nil }

            let mergedCondition: PlatformCondition?
            if let dependencyCondition, let condition {
                switch dependencyCondition.intersection(condition) {
                case .incompatible:
                    return nil
                case let .condition(condition):
                    mergedCondition = condition
                }
            } else {
                mergedCondition = dependencyCondition ?? condition
            }

            return GraphTargetReference(
                target: GraphTarget(path: path, target: target, project: project),
                condition: mergedCondition
            )
        }
    }

    private func targetsWithExternalDependencies(
        graph: Graph,
        graphTraverser: GraphTraverser,
        externalDependencies: [String: [TargetDependency]]
    ) -> Set<GraphTarget> {
        let directTargets = graphTraverser.targetsWithExternalDependencies()
        let packageProductTargets = graph.dependencies.compactMap { dependency, dependencies -> GraphTarget? in
            guard case let .target(name, path, _) = dependency else { return nil }

            let hasResolvedPackageProducts = dependencies.contains { dependency in
                guard case let .packageProduct(_, product, _) = dependency else { return false }
                return externalDependencies[product] != nil || externalDependencies[product.lowercased()] != nil
            }

            guard hasResolvedPackageProducts,
                  let project = graph.projects[path],
                  let target = project.targets[name]
            else { return nil }

            return GraphTarget(path: path, target: target, project: project)
        }

        return directTargets.union(packageProductTargets)
    }

    private func normalizeExternalDependencies(
        _ externalDependencies: [String: [TargetDependency]]
    ) -> [String: [TargetDependency]] {
        var normalized = externalDependencies
        for (key, value) in externalDependencies {
            normalized[key.lowercased()] = value
        }
        return normalized
    }
}
