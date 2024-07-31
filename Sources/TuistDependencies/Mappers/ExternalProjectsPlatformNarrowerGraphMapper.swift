import Foundation
import TuistCore
import XcodeGraph

/**
 When Swift Packages don't declare the platforms that they support, the Swift Package Manager defaults the value
 to 'support all the platforms'. This default behaviour is inherited into the Xcode projects that we generate off the packages
 and that causes compilation issues. Xcode must resolve this issue at build-time by cascading the platform requirements
 down from nodes in the graph that are closer to the root. This is a behaviour that we need to copy over to Tuist. In our case
 the logic is executed at generation time.
 */
public struct ExternalProjectsPlatformNarrowerGraphMapper: GraphMapping { // swiftlint:disable:this type_name
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [TuistCore.SideEffectDescriptor], MapperEnvironment) {
        logger.debug("Transforming graph \(graph.name): Aligning external target platforms with locals'")

        // If the project has no external dependencies we skip this.
        if graph.projects.values.first(where: { $0.isExternal }) == nil {
            return (graph, [], environment)
        }

        var graph = graph
        let externalTargetSupportedPlatforms = GraphTraverser(graph: graph).externalTargetSupportedPlatforms()

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { _, target in
                let mappedTarget = mapTarget(
                    target: target,
                    project: project,
                    externalTargetSupportedPlatforms: externalTargetSupportedPlatforms
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
        externalTargetSupportedPlatforms: [GraphTarget: Set<Platform>]
    ) -> Target {
        /**
         We only include the destinations whose platform is included in the list of the target supported platforms.
         */
        var target = target
        let graphTarget = GraphTarget(path: project.path, target: target, project: project)
        if project.isExternal, let targetFilteredPlatforms = externalTargetSupportedPlatforms[graphTarget] {
            target.destinations = target.destinations.filter { destination in
                targetFilteredPlatforms.contains(destination.platform)
            }

            // By changing the destinations we also need to adapt the deployment targets accordingly to account for possibly
            // removed destinations
            target.deploymentTargets = .init(
                iOS: targetFilteredPlatforms.contains(.iOS) ? target.deploymentTargets.iOS : nil,
                macOS: targetFilteredPlatforms.contains(.macOS) ? target.deploymentTargets.macOS : nil,
                watchOS: targetFilteredPlatforms.contains(.watchOS) ? target.deploymentTargets.watchOS : nil,
                tvOS: targetFilteredPlatforms.contains(.tvOS) ? target.deploymentTargets.tvOS : nil,
                visionOS: targetFilteredPlatforms.contains(.visionOS) ? target.deploymentTargets.visionOS : nil
            )
        }
        return target
    }
}
