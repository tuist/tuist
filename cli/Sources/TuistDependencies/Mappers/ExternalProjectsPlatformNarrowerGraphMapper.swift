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
        let externalTargetSupportedDestinations = graphTraverser.externalTargetSupportedDestinations()

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
}
