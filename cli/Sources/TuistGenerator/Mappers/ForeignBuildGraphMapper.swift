import Foundation
import Path
import TuistCore
import XcodeGraph

/// Transforms `.foreignBuild` dependencies into concrete aggregate-style targets and binary dependencies.
///
/// For each unique `.foreignBuild` dependency (deduplicated by `name`):
/// 1. Creates a synthetic target with a `rawScriptBuildPhase` that runs the build script
/// 2. Replaces the `.foreignBuild` dependency in consuming targets with:
///    - A `.target` dependency on the synthetic script-running target (to ensure build ordering)
///    - The resolved binary dependency (`.xcframework`, `.framework`, or `.library`)
public final class ForeignBuildGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph

        struct ForeignBuildInfo {
            let name: String
            let script: String
            let output: TargetDependency
            let projectPath: AbsolutePath
        }

        var foreignBuilds: [String: ForeignBuildInfo] = [:]

        for (projectPath, project) in graph.projects {
            for target in project.targets.values {
                for dependency in target.dependencies {
                    guard case let .foreignBuild(name, script, output, _, _) = dependency else { continue }
                    if foreignBuilds[name] == nil {
                        foreignBuilds[name] = ForeignBuildInfo(
                            name: name,
                            script: script,
                            output: output,
                            projectPath: projectPath
                        )
                    }
                }
            }
        }

        if foreignBuilds.isEmpty {
            return (graph, [], environment)
        }

        for (_, info) in foreignBuilds {
            let projectPath = info.projectPath
            guard var project = graph.projects[projectPath] else { continue }

            let syntheticTarget = Target(
                name: info.name,
                destinations: destinationsForProject(project),
                product: .framework,
                productName: nil,
                bundleId: "tuist.foreignBuild.\(info.name)",
                filesGroup: .group(name: info.name),
                rawScriptBuildPhases: [
                    RawScriptBuildPhase(
                        name: "Build \(info.name)",
                        script: info.script,
                        showEnvVarsInLog: false,
                        hashable: false
                    ),
                ],
                metadata: .metadata(tags: ["tuist:foreign-build"])
            )

            project.targets[info.name] = syntheticTarget
            graph.projects[projectPath] = project
        }

        for (projectPath, project) in graph.projects {
            var updatedProject = project
            var projectModified = false

            for (targetName, target) in project.targets {
                var updatedDependencies: [TargetDependency] = []
                var targetModified = false

                for dependency in target.dependencies {
                    guard case let .foreignBuild(name, _, output, _, condition) = dependency else {
                        updatedDependencies.append(dependency)
                        continue
                    }

                    targetModified = true
                    updatedDependencies.append(.target(name: name, status: .required, condition: condition))
                    updatedDependencies.append(output.withCondition(condition))
                }

                if targetModified {
                    var updatedTarget = target
                    updatedTarget.dependencies = updatedDependencies
                    updatedProject.targets[targetName] = updatedTarget
                    projectModified = true
                }
            }

            if projectModified {
                graph.projects[projectPath] = updatedProject
            }
        }

        return (graph, [], environment)
    }

    private func destinationsForProject(_ project: Project) -> Destinations {
        let allDestinations = project.targets.values.flatMap(\.destinations)
        return Set(allDestinations)
    }
}
