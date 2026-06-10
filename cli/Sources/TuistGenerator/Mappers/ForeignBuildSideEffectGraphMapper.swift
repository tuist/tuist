import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Emits side effects to run foreign build scripts when the output XCFramework doesn't exist on disk.
///
/// This mapper runs **after** cache and tree-shaking mappers, so targets that were replaced by
/// cached binaries or pruned from the graph are no longer present. This prevents unnecessary
/// foreign build script executions for cached targets.
///
/// The XCFramework has to exist on disk at generation time so the project generates with a valid
/// reference. The mode selects which build to materialize: the development XCFramework during regular
/// generation (when declared), the universal one when warming the cache.
public struct ForeignBuildSideEffectGraphMapper: GraphMapping {
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
        var sideEffects = [SideEffectDescriptor]()

        for (projectPath, project) in graph.projects {
            for (_, target) in project.targets {
                guard let foreignBuild = target.foreignBuild else { continue }
                let build = foreignBuild.build(for: mode)

                if try await !fileSystem.exists(build.path) {
                    let script = scriptWithWorkingDirectory(
                        build.script,
                        workingDirectory: foreignBuild.workingDirectory
                    )
                    sideEffects.append(
                        .command(CommandDescriptor(command: [
                            "/bin/sh", "-c",
                            "export SRCROOT=\(projectPath.pathString)\ncd \"$SRCROOT\"\n\(script)",
                        ]))
                    )
                }
            }
        }

        return (graph, sideEffects, environment)
    }

    private func scriptWithWorkingDirectory(_ script: String, workingDirectory: AbsolutePath?) -> String {
        guard let workingDirectory else { return script }
        return "cd \"\(workingDirectory.pathString)\"\n\(script)"
    }
}
