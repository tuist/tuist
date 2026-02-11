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
                    guard case let .foreignBuild(name, script, output, cacheInputs, _) = dependency else {
                        continue
                    }

                    let aggregateTargetName: String
                    if let existing = aggregateTargetsByForeignBuildName[name] {
                        aggregateTargetName = existing
                    } else {
                        aggregateTargetName = "ForeignBuild_\(name)"
                        aggregateTargetsByForeignBuildName[name] = aggregateTargetName

                        let outputPath = Self.outputPath(from: output)
                        let inputPaths = Self.inputPaths(from: cacheInputs)
                        let aggregateTarget = Target(
                            name: aggregateTargetName,
                            destinations: target.destinations,
                            product: .staticLibrary,
                            productName: aggregateTargetName,
                            bundleId: "tuist.foreign-build.\(name)",
                            scripts: [
                                TargetScript(
                                    name: "Foreign Build: \(name)",
                                    order: .pre,
                                    script: .embedded(script),
                                    inputPaths: inputPaths,
                                    outputPaths: outputPath.map { [$0.pathString] } ?? [],
                                    showEnvVarsInLog: false
                                ),
                            ],
                            filesGroup: target.filesGroup,
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

    private static func outputPath(from output: TargetDependency) -> AbsolutePath? {
        switch output {
        case let .framework(path, _, _): return path
        case let .xcframework(path, _, _, _): return path
        case let .library(path, _, _, _): return path
        default: return nil
        }
    }

    private static func inputPaths(from cacheInputs: [ForeignBuildCacheInput]) -> [String] {
        cacheInputs.compactMap { input in
            switch input {
            case let .file(path): return path.pathString
            case let .folder(path): return path.pathString
            case let .glob(pattern): return pattern
            case .script: return nil
            }
        }
    }
}
