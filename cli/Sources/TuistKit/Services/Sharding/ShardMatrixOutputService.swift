import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
import TuistLogging
import TuistServer

@Mockable
public protocol ShardMatrixOutputServicing {
    func output(_ shardPlan: Components.Schemas.ShardPlan) async throws
}

public struct ShardMatrixOutputService: ShardMatrixOutputServicing {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func output(_ shardPlan: Components.Schemas.ShardPlan) async throws {
        for shard in shardPlan.shards {
            Logger.current
                .info(
                    "  Shard \(shard.index): \(shard.test_targets.joined(separator: ", ")) (~\(shard.estimated_duration_ms)ms)"
                )
        }

        let indices = (0 ..< shardPlan.shard_count).map { $0 }

        if let githubOutputPath = Environment.current.variables["GITHUB_OUTPUT"] {
            let outputPath = try AbsolutePath(validating: githubOutputPath)
            let matrixJSON = "{\"shard\":\(indices)}"
            let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
            try await fileSystem.writeText(
                existing + "matrix=\(matrixJSON)\n",
                at: outputPath,
                encoding: .utf8,
                options: [.overwrite]
            )
            Logger.current.debug("GitHub Actions matrix output written.")
        } else {
            let currentDirectory = try await Environment.current.currentWorkingDirectory()
            let outputPath = currentDirectory.appending(component: ".tuist-shard-matrix.json")
            if try await fileSystem.exists(outputPath) {
                try await fileSystem.remove(outputPath)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try await fileSystem.writeAsJSON(shardPlan, at: outputPath, encoder: encoder)
            Logger.current.debug("Shard matrix written to \(outputPath.pathString)")
        }
    }
}
