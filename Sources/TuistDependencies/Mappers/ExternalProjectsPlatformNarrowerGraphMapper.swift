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
public struct ExternalProjectsPlatformNarrowerGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) async throws -> (Graph, [TuistCore.SideEffectDescriptor]) {
        // If the project has no external dependencies we skip this.
        if graph.projects.values.first(where: { $0.isExternal }) == nil {
            return (graph, [])
        }

        var graph = graph
        let externalTargetSupportedPlatforms = GraphTraverser(graph: graph).externalTargetSupportedPlatforms()

        graph.targets = Dictionary(uniqueKeysWithValues: graph.targets.map { projectPath, projectTargets in
            let project = graph.projects[projectPath]!
            let projectTargets = Dictionary(uniqueKeysWithValues: projectTargets.map { targetName, target in
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)
                var target = target

                /**
                 We only include the destinations whose platform is included in the list of the target supported platforms.
                 */
                if project.isExternal, let targetFilteredPlatforms = externalTargetSupportedPlatforms[graphTarget] {
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
}
