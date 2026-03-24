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

        let env = Environment.current.variables
        let indices = (0 ..< shardPlan.shard_count).map { $0 }

        if let githubOutputPath = env["GITHUB_OUTPUT"] {
            try await writeGitHubActionsOutput(indices: indices, outputFilePath: githubOutputPath)
        } else if env["GITLAB_CI"] != nil {
            try await writeGitLabCIOutput(indices: indices)
        } else if env["CIRCLECI"] != nil {
            try await writeCircleCIOutput(indices: indices)
        } else if env["BUILDKITE"] != nil {
            try await writeBuildkiteOutput(indices: indices)
        } else if let cmEnvPath = env["CM_ENV"] {
            try await writeCodemagicOutput(indices: indices, cmEnvPath: cmEnvPath)
        } else {
            try await writeFallbackJSON(shardPlan: shardPlan)
        }
    }

    private func writeGitHubActionsOutput(indices: [Int], outputFilePath: String) async throws {
        let outputPath = try AbsolutePath(validating: outputFilePath)
        let matrixJSON = "{\"shard\":\(indices)}"
        let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
        try await fileSystem.writeText(
            existing + "matrix=\(matrixJSON)\n",
            at: outputPath,
            encoding: .utf8,
            options: [.overwrite]
        )
        Logger.current.debug("GitHub Actions matrix output written.")
    }

    private func writeGitLabCIOutput(indices: [Int]) async throws {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let outputPath = currentDirectory.appending(component: ".tuist-shard-child-pipeline.yml")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        var yaml = ""
        for index in indices {
            yaml += """
                shard-\(index):
                  extends: .tuist-shard
                  variables:
                    TUIST_SHARD_INDEX: "\(index)"\n\n
                """
        }
        try await fileSystem.writeText(yaml, at: outputPath, encoding: .utf8)
        Logger.current.debug("GitLab CI child pipeline written to \(outputPath.pathString)")
    }

    private func writeCircleCIOutput(indices: [Int]) async throws {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let outputPath = currentDirectory.appending(component: ".tuist-shard-continuation.json")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        let indicesString = indices.map { String($0) }.joined(separator: ",")
        let parameters: [String: Any] = [
            "shard-indices": indicesString,
            "shard-count": indices.count,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: parameters,
            options: [.prettyPrinted, .sortedKeys]
        )
        let json = String(data: data, encoding: .utf8) ?? "{}"
        try await fileSystem.writeText(json, at: outputPath, encoding: .utf8)
        Logger.current.debug("CircleCI continuation parameters written to \(outputPath.pathString)")
    }

    private func writeBuildkiteOutput(indices: [Int]) async throws {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let outputPath = currentDirectory.appending(component: ".tuist-shard-pipeline.yml")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        var yaml = "steps:\n"
        for index in indices {
            yaml += """
                  - label: "Shard #\(index)"
                    env:
                      TUIST_SHARD_INDEX: "\(index)"\n\n
                """
        }
        try await fileSystem.writeText(yaml, at: outputPath, encoding: .utf8)
        Logger.current.debug("Buildkite pipeline written to \(outputPath.pathString)")
    }

    private func writeCodemagicOutput(indices: [Int], cmEnvPath: String) async throws {
        let outputPath = try AbsolutePath(validating: cmEnvPath)
        let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
        let matrixJSON = "{\"shard\":\(indices)}"
        try await fileSystem.writeText(
            existing + "TUIST_SHARD_MATRIX=\(matrixJSON)\nTUIST_SHARD_COUNT=\(indices.count)\n",
            at: outputPath,
            encoding: .utf8,
            options: [.overwrite]
        )
        Logger.current.debug("Codemagic environment variables written to CM_ENV.")
    }

    private func writeFallbackJSON(shardPlan: Components.Schemas.ShardPlan) async throws {
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
