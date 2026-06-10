import FileSystem
import Foundation
import Path
import TuistAlert
import TuistCore
import XcodeGraph

/// Selects which XCFramework build a foreign-build mapper acts on.
public enum ForeignBuildMode: Sendable {
    /// Regular generation: build the thinner development XCFramework when one is declared.
    case incremental
    /// Cache warming: build the universal XCFramework.
    case universal
}

/// Configures foreign build targets with script build phases and wires up linking dependencies.
///
/// For each target where `target.foreignBuild != nil`:
/// 1. Configures the target as an aggregate that runs the build script for the selected XCFramework. In `.incremental`
///    mode the development XCFramework is built when declared, otherwise the universal one.
/// 2. For each consuming target that depends on this foreign build target, inserts a `foreignBuildOutput` graph
///    dependency so the XCFramework is linked (and embedded when dynamic).
///
/// Side effects (running the build script ahead of time) are handled separately by
/// `ForeignBuildSideEffectGraphMapper`, which runs after cache and tree-shaking mappers so that cached/pruned
/// targets don't trigger unnecessary builds.
public struct ForeignBuildGraphMapper: GraphMapping {
    private let mode: ForeignBuildMode
    private let fileSystem: FileSystem

    public init(mode: ForeignBuildMode = .incremental, fileSystem: FileSystem = FileSystem()) {
        self.mode = mode
        self.fileSystem = fileSystem
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph

        var foreignBuildTargets = [GraphDependency: ForeignBuild.XCFrameworkBuild]()

        for (projectPath, project) in graph.projects {
            var updatedProject = project

            for (targetName, target) in project.targets {
                guard let foreignBuild = target.foreignBuild else { continue }

                let build = foreignBuild.build(for: mode)
                let effectiveScript = scriptWithWorkingDirectory(
                    build.script,
                    workingDirectory: foreignBuild.workingDirectory,
                    projectPath: projectPath
                )
                let inputPaths = try await inputPaths(from: foreignBuild.inputs, targetName: targetName)

                var updatedTarget = target
                updatedTarget.scripts = [
                    TargetScript(
                        name: "Foreign Build: \(targetName)",
                        order: .pre,
                        script: .embedded(effectiveScript),
                        inputPaths: inputPaths,
                        outputPaths: [build.path.pathString],
                        showEnvVarsInLog: false,
                        basedOnDependencyAnalysis: inputPaths.isEmpty ? false : nil
                    ),
                ]
                updatedTarget.metadata = .metadata(
                    tags: target.metadata.tags.union(["tuist:foreign-build-aggregate"])
                )
                updatedProject.targets[targetName] = updatedTarget

                let graphDep = GraphDependency.target(name: targetName, path: projectPath)
                foreignBuildTargets[graphDep] = build
                if graph.dependencies[graphDep] == nil {
                    graph.dependencies[graphDep] = Set()
                }
            }

            graph.projects[projectPath] = updatedProject
        }

        for (consumer, deps) in graph.dependencies {
            for dep in deps {
                guard let build = foreignBuildTargets[dep], case let .target(name, _, _) = dep else { continue }
                let foreignBuildOutputDep = GraphDependency.foreignBuildOutput(
                    GraphDependency.ForeignBuildOutput(
                        name: name,
                        path: build.path,
                        linking: build.linking
                    )
                )
                graph.dependencies[consumer, default: Set()].insert(foreignBuildOutputDep)
            }
        }

        return (graph, [], environment)
    }

    private func scriptWithWorkingDirectory(
        _ script: String,
        workingDirectory: AbsolutePath?,
        projectPath: AbsolutePath
    ) -> String {
        guard let workingDirectory else { return script }
        let relativePath = workingDirectory.relative(to: projectPath).pathString
        return "cd \"$SRCROOT/\(relativePath)\"\n\(script)"
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

extension ForeignBuild {
    /// The XCFramework build to produce for the given mode: the development build in `.incremental` mode when
    /// declared, otherwise the universal build.
    func build(for mode: ForeignBuildMode) -> XCFrameworkBuild {
        switch mode {
        case .incremental:
            return developmentXCFramework ?? xcframework
        case .universal:
            return xcframework
        }
    }
}
