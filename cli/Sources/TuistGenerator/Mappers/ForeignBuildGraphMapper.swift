import Foundation
import Path
import TuistCore
import XcodeGraph

/// Transforms `.foreignBuild` dependencies into concrete binary dependencies with script build phases.
///
/// For each `.foreignBuild` dependency:
/// 1. Adds a `rawScriptBuildPhase` to the consuming target that runs the build script
/// 2. Replaces the `.foreignBuild` dependency with the resolved binary dependency (`.xcframework`, `.framework`, or `.library`)
public final class ForeignBuildGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph
        var hasChanges = false

        for (projectPath, project) in graph.projects {
            var updatedProject = project
            var projectModified = false

            for (targetName, target) in project.targets {
                var updatedDependencies: [TargetDependency] = []
                var scriptPhases = target.rawScriptBuildPhases
                var targetModified = false

                for dependency in target.dependencies {
                    guard case let .foreignBuild(name, script, output, _, condition) = dependency else {
                        updatedDependencies.append(dependency)
                        continue
                    }

                    targetModified = true
                    scriptPhases.append(RawScriptBuildPhase(
                        name: "Foreign Build: \(name)",
                        script: script,
                        showEnvVarsInLog: false,
                        hashable: false
                    ))
                    updatedDependencies.append(output.withCondition(condition))
                }

                if targetModified {
                    var updatedTarget = target
                    updatedTarget.dependencies = updatedDependencies
                    updatedTarget.rawScriptBuildPhases = scriptPhases
                    updatedProject.targets[targetName] = updatedTarget
                    projectModified = true
                }
            }

            if projectModified {
                graph.projects[projectPath] = updatedProject
                hasChanges = true
            }
        }

        return (graph, [], environment)
    }
}
