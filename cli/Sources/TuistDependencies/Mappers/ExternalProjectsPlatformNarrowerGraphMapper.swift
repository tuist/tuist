import Foundation
import Logging
import Path
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
        let localPackageTests = graphTraverser.allExternalTargets().filter {
            $0.target.metadata.tags.contains(TargetTags.localSwiftPackageTest)
        }
        let narrowedTests = Dictionary(uniqueKeysWithValues: localPackageTests.map { test in
            let target = mapTarget(
                target: test.target,
                project: test.project,
                externalTargetSupportedDestinations: externalTargetSupportedDestinations,
                projects: graph.projects
            )
            return (test, GraphTarget(path: test.path, target: target, project: test.project))
        })
        if !narrowedTests.isEmpty {
            // Infer test platforms from production consumers before using the tests as roots,
            // so test-only dependencies inherit those platforms without widening the runtime graph.
            externalTargetSupportedDestinations = graphTraverser.externalTargetSupportedDestinations(
                including: Set(narrowedTests.values)
            )
            for (test, narrowedTest) in narrowedTests {
                externalTargetSupportedDestinations[test] = narrowedTest.target.destinations
            }
        }

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { _, target in
                let mappedTarget = mapTarget(
                    target: target,
                    project: project,
                    externalTargetSupportedDestinations: externalTargetSupportedDestinations,
                    projects: graph.projects
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
        externalTargetSupportedDestinations: [GraphTarget: Set<Destination>],
        projects: [AbsolutePath: Project]
    ) -> Target {
        var target = target
        let graphTarget = GraphTarget(path: project.path, target: target, project: project)
        guard case .external = project.type else { return target }

        var targetFilteredDestinations = externalTargetSupportedDestinations[graphTarget]

        // Orphan local SPM test targets aren't reached by the top-down traversal. Union
        // destinations of the test's linkable deps — non-linkable deps (macros, bundles)
        // don't constrain runtime platforms.
        if targetFilteredDestinations == nil,
           target.metadata.tags.contains(TargetTags.localSwiftPackageTest)
        {
            let linkableDestinations = target.dependencies.compactMap { dep -> Set<Destination>? in
                guard let (depGraphTarget, dependencyCondition) = linkableDependency(dep, project: project, projects: projects)
                else { return nil }
                guard let depDestinations = externalTargetSupportedDestinations[depGraphTarget] else { return nil }

                return orphanTestDependencyDestinations(
                    depDestinations,
                    target: target,
                    dependencyCondition: dependencyCondition
                )
            }
            if let first = linkableDestinations.first {
                targetFilteredDestinations = linkableDestinations.dropFirst().reduce(first) { $0.union($1) }
            }
        }

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

    private func linkableDependency(
        _ dependency: TargetDependency,
        project: Project,
        projects: [AbsolutePath: Project]
    ) -> (GraphTarget, PlatformCondition?)? {
        let dependencyProject: Project
        let name: String
        let condition: PlatformCondition?
        switch dependency {
        case let .target(targetName, _, dependencyCondition):
            dependencyProject = project
            name = targetName
            condition = dependencyCondition
        case let .project(targetName, path, _, dependencyCondition):
            guard let resolvedProject = projects[path] else { return nil }
            dependencyProject = resolvedProject
            name = targetName
            condition = dependencyCondition
        default:
            return nil
        }
        guard let target = dependencyProject.targets[name], target.isLinkable() else { return nil }
        return (GraphTarget(path: dependencyProject.path, target: target, project: dependencyProject), condition)
    }

    private func orphanTestDependencyDestinations(
        _ destinations: Set<Destination>,
        target: Target,
        dependencyCondition: PlatformCondition?
    ) -> Set<Destination>? {
        let inheritedDestinations = destinations.intersection(target.destinations)

        guard let dependencyCondition,
              let targetCondition = PlatformCondition.when(target.dependencyPlatformFilters)
        else {
            return inheritedDestinations
        }

        switch targetCondition.intersection(dependencyCondition) {
        case .incompatible:
            return nil
        case let .condition(condition):
            guard let condition else { return inheritedDestinations }
            let allowedPlatformFilters = condition.platformFilters
            return inheritedDestinations.filter { allowedPlatformFilters.contains($0.platformFilter) }
        }
    }
}
