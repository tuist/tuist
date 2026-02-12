import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Configures foreign build targets with script build phases and wires up linking dependencies.
///
/// For each target where `target.foreignBuild != nil`:
/// 1. Configures the target as an aggregate (adds the build script phase)
/// 2. For each consuming target that depends on this foreign build target (via `.target(name:)`),
///    inserts a `foreignBuildOutput` graph dependency for linking
/// 3. If the output artifact doesn't exist yet, emits a side effect to run the foreign build script
///    so that the artifact is available for Xcode to resolve file references
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
        var sideEffects = [SideEffectDescriptor]()

        for (projectPath, project) in graph.projects {
            var updatedProject = project

            let foreignBuildTargetNames = Set(
                project.targets.values
                    .filter { $0.foreignBuild != nil }
                    .map(\.name)
            )

            for (targetName, target) in project.targets {
                guard let foreignBuild = target.foreignBuild else { continue }

                let inputPaths = inputPaths(from: foreignBuild.inputs)
                var updatedTarget = target
                updatedTarget.scripts = [
                    TargetScript(
                        name: "Foreign Build: \(targetName)",
                        order: .pre,
                        script: .embedded(foreignBuild.script),
                        inputPaths: inputPaths,
                        outputPaths: [foreignBuild.output.path.pathString],
                        showEnvVarsInLog: false
                    ),
                ]
                updatedTarget.metadata = .metadata(
                    tags: target.metadata.tags.union(["tuist:foreign-build-aggregate"])
                )
                updatedProject.targets[targetName] = updatedTarget

                let foreignBuildGraphDep = GraphDependency.target(name: targetName, path: projectPath)
                if graph.dependencies[foreignBuildGraphDep] == nil {
                    graph.dependencies[foreignBuildGraphDep] = Set()
                }

                if try await !fileSystem.exists(foreignBuild.output.path) {
                    sideEffects.append(
                        .command(CommandDescriptor(command: [
                            "/bin/sh", "-c",
                            "export SRCROOT=\(projectPath.pathString)\ncd \"$SRCROOT\"\n\(foreignBuild.script)",
                        ]))
                    )
                }
            }

            for (targetName, target) in project.targets {
                guard target.foreignBuild == nil else { continue }

                for dependency in target.dependencies {
                    guard case let .target(depName, _, _) = dependency,
                          foreignBuildTargetNames.contains(depName)
                    else { continue }

                    let foreignBuild = project.targets[depName]!.foreignBuild!
                    let consumingTargetGraphDep = GraphDependency.target(name: targetName, path: projectPath)
                    let foreignBuildOutputDep = GraphDependency.foreignBuildOutput(
                        GraphDependency.ForeignBuildOutput(
                            name: depName,
                            path: foreignBuild.output.path,
                            linking: foreignBuild.output.linking
                        )
                    )
                    graph.dependencies[consumingTargetGraphDep, default: Set()].insert(foreignBuildOutputDep)
                }
            }

            graph.projects[projectPath] = updatedProject
        }

        return (graph, sideEffects, environment)
    }

    // MARK: - Helpers

    private func inputPaths(from inputs: [ForeignBuildInput]) -> [String] {
        inputs.compactMap { input in
            switch input {
            case let .file(path): return path.pathString
            case let .folder(path): return path.pathString
            case let .glob(pattern): return pattern
            case .script: return nil
            }
        }
    }
}
