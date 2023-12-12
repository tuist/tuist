import Foundation
import TuistCore
import TuistGraph

/**
 When Swift Packages don't declare the platforms that they support, the Swift Package Manager defaults the value
 to 'support all the platforms'. This default behaviour is inherited into the Xcode projects that we generate off the packages
 and that causes compilation issues. Xcode must resolve this issue at build-time by cascading the platform requirements
 down from nodes in the graph that are closer to the root. This is a behaviour that we need to copy over to Tuist. In our case
 the logic is executed at generation time.
 */
public final class ExternalProjectsPlatformTreeShakerGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) async throws -> (Graph, [TuistCore.SideEffectDescriptor]) {
        var graph = graph

        /**
         One traverse gives us a dictionary that maps graph targets to the platforms they should support
         */
        let targetsToPlatformsDictionary = targetsToPlatformsDictionary(graph: graph)

        graph.targets = Dictionary(uniqueKeysWithValues: graph.targets.map { projectPath, projectTargets in
            let project = graph.projects[projectPath]!
            let projectTargets = Dictionary(uniqueKeysWithValues: projectTargets.map { targetName, target in
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)
                var target = target

                /**
                 We only include the destinations whose platform is included in the list of the target supported platforms.
                 */
                if let targetFilteredPlatforms = targetsToPlatformsDictionary[graphTarget] {
                    target.destinations = target.destinations.filter { destination in
                        targetFilteredPlatforms.contains(destination.platform)
                    }
                }
                return (targetName, target)
            })
            return (projectPath, projectTargets)
        })
        return (graph, [])
    }

    private func targetsToPlatformsDictionary(graph: Graph) -> [GraphTarget: Set<Platform>] {
        let graphTraverser = GraphTraverser(graph: graph)
        var platforms: [GraphTarget: Set<Platform>] = [:]

        graphTraverser.allInternalTargets().forEach { target in
            platforms[target] = target.target.supportedPlatforms
            traverse(
                target: target,
                parentPlatforms: target.target.supportedPlatforms,
                graphTraverser: graphTraverser,
                platforms: &platforms
            )
        }

        return platforms
    }

    private func traverse(
        target: GraphTarget,
        parentPlatforms: Set<Platform>,
        graphTraverser: GraphTraverser,
        platforms: inout [GraphTarget: Set<Platform>]
    ) {
        let dependencies = graphTraverser.directTargetDependenciesWithConditions(path: target.path, name: target.target.name)

        dependencies.forEach { dependencyTarget, dependencyCondition in
            if let dependencyCondition,
               let platformIntersection = PlatformCondition.when(target.target.dependencyPlatformFilters)?
               .intersection(dependencyCondition)
            {
                switch platformIntersection {
                case .incompatible:
                    break
                case let .condition(condition):
                    if let condition {
                        let dependencyPlatforms: [Platform] = condition.platformFilters
                            .map(\.platform)
                            .filter { $0 != nil }
                            .map { $0! }
                        var existingDependencyPlatforms = platforms[dependencyTarget, default: Set()]
                        existingDependencyPlatforms.formUnion(dependencyPlatforms)
                        platforms[dependencyTarget] = existingDependencyPlatforms
                    }
                }
            } else {
                var dependencyPlatforms = platforms[dependencyTarget, default: Set()]
                if dependencyTarget.project.isExternal {
                    dependencyPlatforms
                        .formUnion(intersectExternalPlatforms(
                            parentPlatforms: parentPlatforms,
                            dependencyTarget: dependencyTarget
                        ))
                } else {
                    dependencyPlatforms.formUnion(dependencyTarget.target.supportedPlatforms)
                }
                platforms[dependencyTarget] = dependencyPlatforms
            }
            traverse(
                target: dependencyTarget,
                parentPlatforms: platforms[dependencyTarget, default: Set()],
                graphTraverser: graphTraverser,
                platforms: &platforms
            )
        }
    }

    private func intersectExternalPlatforms(
        parentPlatforms: Set<Platform>,
        dependencyTarget: GraphTarget
    ) -> Set<Platform> {
        let dependencyPlatforms = if dependencyTarget.target.product == .macro {
            // Targets with the 'macro' product are in the Xcode project domain
            // macOS executables and therefore we need to account for that.
            Set<Platform>([.macOS])
        } else {
            parentPlatforms
        }
        return dependencyPlatforms.intersection(dependencyTarget.target.supportedPlatforms)
    }
}
