import FileSystem
import Foundation
import Path
import TuistAlert
import TuistCore
import XcodeGraph

/// Configures foreign build targets with script build phases and wires up linking dependencies.
///
/// For each target where `target.foreignBuild != nil`:
/// 1. Configures the target as an aggregate (adds the build script phase)
/// 2. For each consuming target that depends on this foreign build target (via `.target(name:)` or `.project(target:path:)`),
///    inserts a `foreignBuildOutput` graph dependency for linking
/// 3. When the consumer lives in a different project than the foreign build aggregate, attaches a copy of
///    the build script directly to the consumer. Xcode does not run scripts from aggregate targets in other
///    projects via implicit dependency resolution, so without this the consumer would link a stale artifact.
///
/// Side effects (running the foreign build script) are handled separately by `ForeignBuildSideEffectGraphMapper`,
/// which runs after cache and tree-shaking mappers so that cached/pruned targets don't trigger unnecessary builds.
public struct ForeignBuildGraphMapper: GraphMapping {
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph

        var foreignBuildTargets = [GraphDependency: ResolvedForeignBuild]()

        for (projectPath, project) in graph.projects {
            var updatedProject = project

            for (targetName, target) in project.targets {
                guard let foreignBuild = target.foreignBuild else { continue }

                let inputPaths = try await inputPaths(from: foreignBuild.inputs, targetName: targetName)
                var updatedTarget = target
                updatedTarget.scripts = [
                    TargetScript(
                        name: "Foreign Build: \(targetName)",
                        order: .pre,
                        script: .embedded(foreignBuild.script),
                        inputPaths: inputPaths,
                        outputPaths: [foreignBuild.output.path.pathString],
                        showEnvVarsInLog: false,
                        basedOnDependencyAnalysis: inputPaths.isEmpty ? false : nil
                    ),
                ]
                updatedTarget.metadata = .metadata(
                    tags: target.metadata.tags.union(["tuist:foreign-build-aggregate"])
                )
                updatedProject.targets[targetName] = updatedTarget

                let graphDep = GraphDependency.target(name: targetName, path: projectPath)
                foreignBuildTargets[graphDep] = ResolvedForeignBuild(
                    name: targetName,
                    projectPath: projectPath,
                    info: foreignBuild,
                    resolvedInputPaths: inputPaths
                )
                if graph.dependencies[graphDep] == nil {
                    graph.dependencies[graphDep] = Set()
                }
            }

            graph.projects[projectPath] = updatedProject
        }

        for (consumer, deps) in graph.dependencies {
            for dep in deps {
                guard let resolved = foreignBuildTargets[dep] else { continue }
                let foreignBuildOutputDep = GraphDependency.foreignBuildOutput(
                    GraphDependency.ForeignBuildOutput(
                        name: resolved.name,
                        path: resolved.info.output.path,
                        linking: resolved.info.output.linking
                    )
                )
                graph.dependencies[consumer, default: Set()].insert(foreignBuildOutputDep)

                guard case let .target(consumerName, consumerPath, _) = consumer,
                      consumerPath != resolved.projectPath,
                      let consumerProject = graph.projects[consumerPath],
                      let consumerTarget = consumerProject.targets[consumerName],
                      consumerTarget.foreignBuild == nil
                else { continue }

                let scriptName = "Foreign Build: \(resolved.name)"
                if consumerTarget.scripts.contains(where: { $0.name == scriptName }) { continue }

                let wrappedScript = """
                export SRCROOT=\(resolved.projectPath.pathString)
                cd "$SRCROOT"
                \(resolved.info.script)
                """
                var updatedTarget = consumerTarget
                updatedTarget.scripts.insert(
                    TargetScript(
                        name: scriptName,
                        order: .pre,
                        script: .embedded(wrappedScript),
                        inputPaths: resolved.resolvedInputPaths,
                        outputPaths: [resolved.info.output.path.pathString],
                        showEnvVarsInLog: false,
                        basedOnDependencyAnalysis: resolved.resolvedInputPaths.isEmpty ? false : nil
                    ),
                    at: 0
                )
                var updatedProject = consumerProject
                updatedProject.targets[consumerName] = updatedTarget
                graph.projects[consumerPath] = updatedProject
            }
        }

        return (graph, [], environment)
    }

    private struct ResolvedForeignBuild {
        let name: String
        let projectPath: AbsolutePath
        let info: ForeignBuild
        let resolvedInputPaths: [String]
    }

    private func inputPaths(from inputs: [ForeignBuild.Input], targetName: String) async throws -> [String] {
        var pathStrings: [String] = []

        for input in inputs {
            switch input {
            case let .file(path):
                pathStrings.append(path.pathString)
            case let .folder(path):
                let filePathStrings = try await fileSystem.glob(directory: path, include: ["**/*"])
                    .collect()
                    .concurrentFilter {
                        try await fileSystem.exists($0, isDirectory: false)
                    }
                    .map(\.pathString)
                if filePathStrings.isEmpty {
                    AlertController.current.warning(.alert(
                        "Foreign build folder input '\(path.pathString)' for target '\(targetName)' is empty or does not exist. Verify the path is correct, otherwise Xcode will not detect changes to files in this folder."
                    ))
                }
                pathStrings.append(contentsOf: filePathStrings)
            case .script:
                break
            }
        }

        if pathStrings.isEmpty {
            AlertController.current.warning(.alert(
                "Foreign build target '\(targetName)' has no resolvable input file paths, so the script will run on every build. This is fine when the underlying build system handles its own incrementality; otherwise, declare inputs so Xcode can skip the script when nothing changed."
            ))
        }

        return pathStrings
    }
}
