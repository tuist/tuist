import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Configures foreign build targets with script build phases and wires up linking dependencies.
///
/// For each target where `target.foreignBuild != nil`:
/// 1. Configures the target as an aggregate (adds the build script phase)
/// 2. For each consuming target that depends on this foreign build target (via `.target(name:)` or `.project(target:path:)`),
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

        var foreignBuildTargets = [GraphDependency: (name: String, info: ForeignBuildInfo)]()

        for (projectPath, project) in graph.projects {
            var updatedProject = project

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

                let graphDep = GraphDependency.target(name: targetName, path: projectPath)
                foreignBuildTargets[graphDep] = (name: targetName, info: foreignBuild)
                if graph.dependencies[graphDep] == nil {
                    graph.dependencies[graphDep] = Set()
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

            graph.projects[projectPath] = updatedProject
        }

        for (consumer, deps) in graph.dependencies {
            for dep in deps {
                guard let (name, foreignBuild) = foreignBuildTargets[dep] else { continue }
                let foreignBuildOutputDep = GraphDependency.foreignBuildOutput(
                    GraphDependency.ForeignBuildOutput(
                        name: name,
                        path: foreignBuild.output.path,
                        linking: foreignBuild.output.linking
                    )
                )
                graph.dependencies[consumer, default: Set()].insert(foreignBuildOutputDep)
            }
        }

        return (graph, sideEffects, environment)
    }

    private func inputPaths(from inputs: [ForeignBuildInput]) -> [String] {
        inputs.compactMap { input in
            switch input {
            case let .file(path): return path.pathString
            case let .folder(path): return path.pathString
            case .script: return nil
            }
        }
    }
}