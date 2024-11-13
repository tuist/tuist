import Foundation
import Path
import TuistCore
import XcodeGraph

public final class TreeShakePrunedTargetsGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (
        Graph, [SideEffectDescriptor], MapperEnvironment
    ) {
        logger.debug("Transforming graph \(graph.name): Tree-shaking nodes")
        let sourceTargets: Set<TargetReference> = Set(
            graph.projects.flatMap { projectPath, project -> [TargetReference] in
                return project.targets.compactMap { _, target -> TargetReference? in
                    if target.prune { return nil }
                    return TargetReference(projectPath: projectPath, name: target.name)
                }
            }
        )

        // If the number of source targets matches the number of targets in the graph there's nothing to be pruned.
        if sourceTargets.count == graph.projects.values.flatMap(\.targets.values).count {
            return (graph, [], environment)
        }

        var treeShakenProjects: [AbsolutePath: Project] = [:]
        var treeShakenDependencies: [GraphDependency: Set<GraphDependency>] = graph.dependencies

        for (projectPath, project) in graph.projects {
            let (treeShakenTargets, projecttreeShakenDependencies) = treeShake(
                targets: Array(project.targets.values),
                dependencies: graph.dependencies,
                path: projectPath,
                graph: graph,
                sourceTargets: sourceTargets
            )
            if !treeShakenTargets.isEmpty {
                let schemes = treeShake(
                    schemes: project.schemes,
                    sourceTargets: sourceTargets
                )
                var project = project
                project.schemes = schemes
                project.targets = Dictionary(
                    uniqueKeysWithValues: treeShakenTargets.map { ($0.name, $0) }
                )
                treeShakenProjects[projectPath] = project
            }
            for (fromDependency, toDependencies) in projecttreeShakenDependencies {
                treeShakenDependencies[fromDependency] = toDependencies
            }
        }

        let workspace = treeShake(
            workspace: graph.workspace,
            projects: Array(treeShakenProjects.values),
            sourceTargets: sourceTargets
        )

        var graph = graph
        graph.workspace = workspace
        graph.projects = treeShakenProjects
        graph.dependencies = treeShakenDependencies
        return (graph, [], environment)
    }

    fileprivate func treeShake(
        workspace: Workspace, projects: [Project], sourceTargets: Set<TargetReference>
    ) -> Workspace {
        let projects = workspace.projects.filter { projects.map(\.path).contains($0) }
        let schemes = treeShake(schemes: workspace.schemes, sourceTargets: sourceTargets)
        var workspace = workspace
        workspace.schemes = schemes
        workspace.projects = projects
        return workspace
    }

    fileprivate func treeShake(
        targets: [Target],
        dependencies: [GraphDependency: Set<GraphDependency>],
        path: AbsolutePath,
        graph: Graph,
        sourceTargets: Set<TargetReference>
    ) -> (targets: [Target], dependencies: [GraphDependency: Set<GraphDependency>]) {
        var treeShakenTargets: [Target] = []
        var treeShakenDependencies: [GraphDependency: Set<GraphDependency>] = [:]

        for target in targets {
            guard var target = graph.projects[path]?.targets[target.name] else { continue }
            let targetReference = TargetReference(projectPath: path, name: target.name)
            guard sourceTargets.contains(targetReference) else { continue }

            /**
             Since we have target.dependencies and graph.dependencies (duplicated), we have to apply the changes in both sides.
             Once we refactor the code to only depend on graph.dependencies, we can get rid of these duplications.
             */
            target.dependencies = target.dependencies.filter { dependency in
                switch dependency {
                case let .target(targetDependencyName, _, _):
                    return sourceTargets.contains(
                        TargetReference(projectPath: path, name: targetDependencyName)
                    )
                case let .project(targetDependencyName, targetDependencyProjectPath, _, _):
                    return sourceTargets.contains(
                        TargetReference(
                            projectPath: targetDependencyProjectPath,
                            name: targetDependencyName
                        )
                    )
                default:
                    return true
                }
            }
            treeShakenTargets.append(target)

            if let targetGraphDependency = dependencies.keys.first(where: { dependency -> Bool in
                switch dependency {
                case let .target(dependencyTargetName, dependencyPath, _):
                    return target.name == dependencyTargetName && path == dependencyPath
                default:
                    return false
                }
            }) {
                treeShakenDependencies[targetGraphDependency] = Set(
                    dependencies[targetGraphDependency, default: Set()]
                        .compactMap { dependency in
                            switch dependency {
                            case let .target(dependencyName, dependencyProjectPath, _):
                                /**
                                 If a target dependency a target depends on is tree-shaked, that dependency should be removed.
                                 This happens in scenarios where a external target (iOS and tvOS framework) conditionally depends on
                                 framework based on the platform. We have logic to prune unneceessary platforms from the external
                                 part of the graph.
                                 */
                                if sourceTargets.contains(
                                    TargetReference(
                                        projectPath: dependencyProjectPath,
                                        name: dependencyName
                                    )
                                ) {
                                    return dependency
                                } else {
                                    return nil
                                }
                            default:
                                return dependency
                            }
                        }
                )
            }
        }
        return (targets: treeShakenTargets, dependencies: treeShakenDependencies)
    }

    fileprivate func treeShake(schemes: [Scheme], sourceTargets: Set<TargetReference>) -> [Scheme] {
        schemes.compactMap { scheme -> Scheme? in
            var scheme = scheme

            if let buildAction = scheme.buildAction {
                scheme.buildAction?.targets = buildAction.targets.filter(sourceTargets.contains)
            }

            if let testAction = scheme.testAction {
                scheme.testAction?.targets = testAction.targets.filter {
                    sourceTargets.contains($0.target)
                }
                scheme.testAction?.codeCoverageTargets = testAction.codeCoverageTargets.filter(
                    sourceTargets.contains
                )
            }

            let hasBuildTargets = !(scheme.buildAction?.targets ?? []).isEmpty
            let hasTestTargets = !(scheme.testAction?.targets ?? []).isEmpty
            let hasTestPlans = !(scheme.testAction?.testPlans ?? []).isEmpty
            guard hasBuildTargets || hasTestTargets || hasTestPlans else {
                return nil
            }

            if let expandVariableFromTarget = scheme.runAction?.expandVariableFromTarget,
               !sourceTargets.contains(expandVariableFromTarget)
            {
                return nil
            }

            if let expandVariableFromTarget = scheme.testAction?.expandVariableFromTarget,
               !sourceTargets.contains(expandVariableFromTarget)
            {
                return nil
            }

            return scheme
        }
    }
}
