import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Emits side effects to run foreign build scripts when the output artifact doesn't exist on disk.
///
/// This mapper runs **after** cache and tree-shaking mappers, so targets that were replaced by
/// cached binaries or pruned from the graph are no longer present. This prevents unnecessary
/// foreign build script executions for cached targets.
public struct ForeignBuildSideEffectGraphMapper: GraphMapping {
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem = FileSystem()) {
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

                if try await !fileSystem.exists(foreignBuild.output.path) {
                    sideEffects.append(
                        .command(CommandDescriptor(command: [
                            "/bin/sh", "-c",
                            "export SRCROOT=\(projectPath.pathString)\ncd \"$SRCROOT\"\n\(foreignBuild.script)",
                        ]))
                    )
                }
            }
        }

        return (graph, sideEffects, environment)
    }
}
