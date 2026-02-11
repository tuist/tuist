import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Transforms `.foreignBuild` dependencies into aggregate targets with script build phases.
///
/// For each unique `.foreignBuild` dependency in the project:
/// 1. Creates a `PBXAggregateTarget` (via a tagged target) that runs the foreign build script
/// 2. Adds a target dependency from the consuming target to the aggregate target (for build ordering)
/// 3. The consuming target retains the `foreignBuildOutput` graph dependency (set by GraphLoader) for linking
/// 4. If the output artifact doesn't exist yet, runs the foreign build script so that the artifact
///    is available for Xcode to resolve file references during project generation
public final class ForeignBuildGraphMapper: GraphMapping {
    private let fileSystem: FileSystem
    private let scriptRunner: @Sendable (_ name: String, _ script: String, _ projectPath: AbsolutePath) throws -> Void

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
        self.scriptRunner = Self.runScript
    }

    init(
        fileSystem: FileSystem = FileSystem(),
        scriptRunner: @escaping @Sendable (_ name: String, _ script: String, _ projectPath: AbsolutePath) throws -> Void
    ) {
        self.fileSystem = fileSystem
        self.scriptRunner = scriptRunner
    }

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
                    guard case let .foreignBuild(name, script, output, inputs, _) = dependency else {
                        continue
                    }

                    let aggregateTargetName: String
                    if let existing = aggregateTargetsByForeignBuildName[name] {
                        aggregateTargetName = existing
                    } else {
                        aggregateTargetName = "ForeignBuild_\(name)"
                        aggregateTargetsByForeignBuildName[name] = aggregateTargetName

                        let inputPaths = Self.inputPaths(from: inputs)
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
                                    outputPaths: [output.path.pathString],
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

                        if try await !fileSystem.exists(output.path) {
                            try scriptRunner(name, script, projectPath)
                        }
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

    // MARK: - Script execution

    private static func runScript(_ name: String, _ script: String, projectPath: AbsolutePath) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath.pathString)
        var env = ProcessInfo.processInfo.environment
        env["SRCROOT"] = projectPath.pathString
        process.environment = env
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ForeignBuildError.scriptFailed(exitCode: Int(process.terminationStatus))
        }
    }

    // MARK: - Helpers

    private static func inputPaths(from inputs: [ForeignBuildInput]) -> [String] {
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

enum ForeignBuildError: LocalizedError {
    case scriptFailed(exitCode: Int)

    var errorDescription: String? {
        switch self {
        case let .scriptFailed(exitCode):
            return "Foreign build script failed with exit code \(exitCode)"
        }
    }
}
