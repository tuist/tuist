import Foundation
import Logging
import Path
import TuistCore
import XcodeGraph

public struct TreeShakePrunedTargetsGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (
        Graph, [SideEffectDescriptor], MapperEnvironment
    ) {
        Logger.current.debug("Transforming graph \(graph.name): Tree-shaking nodes")
        var sourceTargets: Set<TargetReference> = []
        var prunedTargets: Set<TargetReference> = []
        for (projectPath, project) in graph.projects {
            for target in project.targets.values {
                let reference = TargetReference(projectPath: projectPath, name: target.name)
                if target.metadata.tags.contains("tuist:prunable") {
                    prunedTargets.insert(reference)
                } else {
                    sourceTargets.insert(reference)
                }
            }
        }

        // If nothing was tagged prunable there's nothing to be pruned.
        if prunedTargets.isEmpty {
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
                    sourceTargets: sourceTargets,
                    prunedTargets: prunedTargets
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
            sourceTargets: sourceTargets,
            prunedTargets: prunedTargets
        )

        var graph = graph
        graph.workspace = workspace
        graph.projects = treeShakenProjects
        graph.dependencies = treeShakenDependencies
        return (graph, [], environment)
    }

    fileprivate func treeShake(
        workspace: Workspace,
        projects: [Project],
        sourceTargets: Set<TargetReference>,
        prunedTargets: Set<TargetReference>
    ) -> Workspace {
        let projectPaths = Set(projects.map(\.path))
        let projects = workspace.projects.filter { projectPaths.contains($0) }
        let schemes = treeShake(
            schemes: workspace.schemes,
            sourceTargets: sourceTargets,
            prunedTargets: prunedTargets
        )
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

            // Since we have `target.dependencies` and `graph.dependencies` (duplicated), we have to apply the changes in both
            // sides.
            // Once we refactor the code to only depend on graph.dependencies, we can get rid of these duplications.
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
                                // If a target dependency a target depends on is tree-shaked, that dependency should be removed.
                                // This happens in scenarios where a external target (iOS and tvOS framework) conditionally
                                // depends on framework based on the platform. We have logic to prune unnecessary platforms from
                                // the external part of the graph.
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

    fileprivate func treeShake(
        schemes: [Scheme],
        sourceTargets: Set<TargetReference>,
        prunedTargets: Set<TargetReference>
    ) -> [Scheme] {
        schemes.compactMap { scheme -> Scheme? in
            var scheme = scheme

            if var buildAction = scheme.buildAction {
                buildAction.targets = buildAction.targets.filter(sourceTargets.contains)
                let buildFallback = buildAction.targets.first
                buildAction.preActions = buildAction.preActions.map {
                    rewriteExecutionActionTarget($0, prunedTargets: prunedTargets, fallback: buildFallback)
                }
                buildAction.postActions = buildAction.postActions.map {
                    rewriteExecutionActionTarget($0, prunedTargets: prunedTargets, fallback: buildFallback)
                }
                scheme.buildAction = buildAction
            }

            if var testAction = scheme.testAction {
                testAction.targets = testAction.targets.filter {
                    sourceTargets.contains($0.target)
                }
                testAction.codeCoverageTargets = testAction.codeCoverageTargets.filter(
                    sourceTargets.contains
                )
                testAction.testPlans = testAction.testPlans?.compactMap {
                    treeShake(testPlan: $0, sourceTargets: sourceTargets)
                }
                // Fall back to a surviving testable in the test action; if there's only a
                // surviving test plan, use its first surviving testable; otherwise fall back
                // to the build action's first surviving buildable.
                // Fall back to a surviving testable in the test action; if there's only a
                // surviving test plan, use its first surviving testable; otherwise fall back
                // to the build action's first surviving buildable.
                let testFallback = testAction.targets.first?.target
                    ?? testAction.testPlans?.lazy.compactMap(\.testTargets.first).first?.target
                    ?? scheme.buildAction?.targets.first
                testAction.preActions = testAction.preActions.map {
                    rewriteExecutionActionTarget($0, prunedTargets: prunedTargets, fallback: testFallback)
                }
                testAction.postActions = testAction.postActions.map {
                    rewriteExecutionActionTarget($0, prunedTargets: prunedTargets, fallback: testFallback)
                }
                scheme.testAction = testAction
            }

            // Clear variable-expansion references when their target has been pruned, rather than
            // dropping the whole scheme. Otherwise, for example, a single cached (and therefore
            // pruned) test target can take an entire aggregate workspace scheme with it — even
            // when the scheme still has many other non-cached test targets that should run.
            if let expandVariableFromTarget = scheme.runAction?.expandVariableFromTarget,
               !sourceTargets.contains(expandVariableFromTarget)
            {
                scheme.runAction?.expandVariableFromTarget = nil
            }
            if let expandVariableFromTarget = scheme.testAction?.expandVariableFromTarget,
               !sourceTargets.contains(expandVariableFromTarget)
            {
                scheme.testAction?.expandVariableFromTarget = nil
            }

            let hasBuildTargets = !(scheme.buildAction?.targets ?? []).isEmpty
            let hasTestTargets = !(scheme.testAction?.targets ?? []).isEmpty
            let hasTestPlans = !(scheme.testAction?.testPlans ?? []).isEmpty
            let runsAFilePathExecutable = scheme.runAction?.filePath != nil

            guard hasBuildTargets || hasTestTargets || hasTestPlans || runsAFilePathExecutable else {
                return nil
            }

            return scheme
        }
    }

    /// Rewrites a pre/post-action's `target` when it names a target this mapper is about to
    /// remove from the graph, swapping in the parent action's first surviving buildable so the
    /// script keeps receiving target-derived build settings (`BUILD_DIR`, `CONFIGURATION`, …).
    ///
    /// Targets that were never in the graph in the first place (e.g. a typo in the manifest)
    /// are left untouched — the existing scheme-target-not-found surface in the generator/
    /// linter then surfaces the mistake instead of silently substituting build settings from
    /// an unrelated target.
    private func rewriteExecutionActionTarget(
        _ action: ExecutionAction,
        prunedTargets: Set<TargetReference>,
        fallback: TargetReference?
    ) -> ExecutionAction {
        guard let original = action.target, prunedTargets.contains(original) else { return action }
        return ExecutionAction(
            title: action.title,
            scriptText: action.scriptText,
            target: fallback,
            shellPath: action.shellPath,
            showEnvVarsInLog: action.showEnvVarsInLog
        )
    }

    private func treeShake(
        testPlan: TestPlan,
        sourceTargets: Set<TargetReference>
    ) -> TestPlan? {
        let testTargets = testPlan.testTargets.filter { sourceTargets.contains($0.target) }
        if testTargets.isEmpty {
            return nil
        } else {
            return TestPlan(
                path: testPlan.path,
                testTargets: testTargets,
                isDefault: testPlan.isDefault,
                kind: testPlan.kind
            )
        }
    }
}
