import Path
import TuistCore
import XcodeGraph

/// Transforms `.foreignBuild` dependencies into aggregate targets with script build phases.
///
/// For each unique `.foreignBuild` dependency in the project:
/// 1. Creates a `PBXAggregateTarget` (via a tagged target) that runs the foreign build script
/// 2. Adds a target dependency from the consuming target to the aggregate target (for build ordering)
/// 3. The consuming target retains the `foreignBuildOutput` graph dependency (set by GraphLoader) for linking
public final class ForeignBuildGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph

        for (projectPath, project) in graph.projects {
            var updatedProject = project
            var projectModified = false

            var aggregateTargetsByForeignBuildName: [String: String] = [:]

            for (targetName, target) in project.targets {
                for dependency in target.dependencies {
                    guard case let .foreignBuild(name, script, _, _, _) = dependency else {
                        continue
                    }

                    let aggregateTargetName: String
                    if let existing = aggregateTargetsByForeignBuildName[name] {
                        aggregateTargetName = existing
                    } else {
                        aggregateTargetName = "ForeignBuild_\(name)"
                        aggregateTargetsByForeignBuildName[name] = aggregateTargetName

                        let aggregateTarget = Target(
                            name: aggregateTargetName,
                            destinations: target.destinations,
                            product: .staticLibrary,
                            productName: aggregateTargetName,
                            bundleId: "tuist.foreign-build.\(name)",
                            filesGroup: target.filesGroup,
                            rawScriptBuildPhases: [
                                RawScriptBuildPhase(
                                    name: "Foreign Build: \(name)",
                                    script: script,
                                    showEnvVarsInLog: false,
                                    hashable: false
                                ),
                            ],
                            metadata: .metadata(tags: ["tuist:foreign-build-aggregate"])
                        )
                        updatedProject.targets[aggregateTargetName] = aggregateTarget
                        projectModified = true

                        let aggregateGraphDep = GraphDependency.target(name: aggregateTargetName, path: projectPath)
                        graph.dependencies[aggregateGraphDep] = Set()
                    }

                    let consumingTargetGraphDep = GraphDependency.target(name: targetName, path: projectPath)
                    let aggregateGraphDep = GraphDependency.target(name: aggregateTargetName, path: projectPath)
                    graph.dependencies[consumingTargetGraphDep, default: Set()].insert(aggregateGraphDep)
                }
            }

            if projectModified {
                graph.projects[projectPath] = updatedProject
            }
        }

        return (graph, [], environment)
    }
}
