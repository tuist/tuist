import FileSystem
import Foundation
import Mockable
import Path
import TuistCI
import TuistEnvironment
import TuistLogging
import TuistServer

@Mockable
public protocol ShardMatrixOutputServicing {
    func output(_ shardPlan: Components.Schemas.ShardPlan) async throws
}

public struct ShardMatrixOutputService: ShardMatrixOutputServicing {
    private let fileSystem: FileSysteming
    private let ciController: CIControlling

    public init(
        fileSystem: FileSysteming = FileSystem(),
        ciController: CIControlling = CIController()
    ) {
        self.fileSystem = fileSystem
        self.ciController = ciController
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
        let ciInfo = ciController.ciInfo()

        switch ciInfo?.provider {
        case .github:
            try await writeGitHubActionsOutput(shardPlan: shardPlan, outputFilePath: env["GITHUB_OUTPUT"]!)
        case .gitlab:
            try await writeGitLabCIOutput(indices: indices, shardPlanId: shardPlan.id)
        case .circleci:
            try await writeCircleCIOutput(indices: indices, shardPlanId: shardPlan.id)
        case .buildkite:
            try await writeBuildkiteOutput(indices: indices, shardPlanId: shardPlan.id)
        case .codemagic:
            try await writeCodemagicOutput(indices: indices, shardPlanId: shardPlan.id, cmEnvPath: env["CM_ENV"]!)
        case .bitrise:
            try await writeBitriseOutput(indices: indices, shardPlanId: shardPlan.id, deployDir: env["BITRISE_DEPLOY_DIR"]!)
        case nil:
            try await writeShardMatrixJSON(shardPlan: shardPlan)
        }
    }

    private func writeGitHubActionsOutput(
        shardPlan: Components.Schemas.ShardPlan,
        outputFilePath: String
    ) async throws {
        let outputPath = try AbsolutePath(validating: outputFilePath)
        let indices = (0 ..< shardPlan.shard_count).map { $0 }
        let matrix: [String: Any] = [
            "shard": indices,
            "include": indices.map { index in
                ["shard": index, "shard_plan_id": shardPlan.id] as [String: Any]
            },
        ]
        let matrixData = try JSONSerialization.data(withJSONObject: matrix, options: [.sortedKeys])
        let matrixJSON = String(data: matrixData, encoding: .utf8) ?? "{}"
        let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
        try await fileSystem.writeText(
            existing + "matrix=\(matrixJSON)\n",
            at: outputPath,
            encoding: .utf8,
            options: [.overwrite]
        )
        Logger.current.debug("GitHub Actions matrix output written.")
    }

    private func writeGitLabCIOutput(indices: [Int], shardPlanId: String) async throws {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let outputPath = currentDirectory.appending(component: ".tuist-shard-child-pipeline.yml")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        var yaml = ""
        for index in indices {
            yaml += "shard-\(index):\n"
            yaml += "  extends: .tuist-shard\n"
            yaml += "  variables:\n"
            yaml += "    TUIST_SHARD_INDEX: \"\(index)\"\n"
            yaml += "    TUIST_SHARD_PLAN_ID: \"\(shardPlanId)\"\n\n"
        }
        try await fileSystem.writeText(yaml, at: outputPath, encoding: .utf8)
        Logger.current.debug("GitLab CI child pipeline written to \(outputPath.pathString)")
    }

    private func writeCircleCIOutput(indices: [Int], shardPlanId: String) async throws {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let outputPath = currentDirectory.appending(component: ".tuist-shard-continuation.json")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        let indicesString = indices.map { String($0) }.joined(separator: ",")
        let parameters: [String: Any] = [
            "shard-indices": indicesString,
            "shard-count": indices.count,
            "shard-plan-id": shardPlanId,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: parameters,
            options: [.prettyPrinted, .sortedKeys]
        )
        let json = String(data: data, encoding: .utf8) ?? "{}"
        try await fileSystem.writeText(json, at: outputPath, encoding: .utf8)
        Logger.current.debug("CircleCI continuation parameters written to \(outputPath.pathString)")
    }

    private func writeBuildkiteOutput(indices: [Int], shardPlanId: String) async throws {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let outputPath = currentDirectory.appending(component: ".tuist-shard-pipeline.yml")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        var yaml = "steps:\n"
        for index in indices {
            yaml += "  - label: \"Shard #\(index)\"\n"
            yaml += "    env:\n"
            yaml += "      TUIST_SHARD_INDEX: \"\(index)\"\n"
            yaml += "      TUIST_SHARD_PLAN_ID: \"\(shardPlanId)\"\n\n"
        }
        try await fileSystem.writeText(yaml, at: outputPath, encoding: .utf8)
        Logger.current.debug("Buildkite pipeline written to \(outputPath.pathString)")
    }

    private func writeCodemagicOutput(indices: [Int], shardPlanId: String, cmEnvPath: String) async throws {
        let outputPath = try AbsolutePath(validating: cmEnvPath)
        let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
        let matrixJSON = "{\"shard\":\(indices)}"
        try await fileSystem.writeText(
            existing +
                "TUIST_SHARD_MATRIX=\(matrixJSON)\nTUIST_SHARD_COUNT=\(indices.count)\nTUIST_SHARD_PLAN_ID=\(shardPlanId)\n",
            at: outputPath,
            encoding: .utf8,
            options: [.overwrite]
        )
        Logger.current.debug("Codemagic environment variables written to CM_ENV.")
    }

    private func writeBitriseOutput(indices: [Int], shardPlanId: String, deployDir: String) async throws {
        let deployPath = try AbsolutePath(validating: deployDir)
        let outputPath = deployPath.appending(component: ".tuist-shard-matrix.json")
        if try await fileSystem.exists(outputPath) {
            try await fileSystem.remove(outputPath)
        }
        let matrixJSON =
            "{\"shard\":\(indices),\"shard_count\":\(indices.count),\"shard_plan_id\":\"\(shardPlanId)\"}"
        try await fileSystem.writeText(matrixJSON, at: outputPath, encoding: .utf8)
        Logger.current.debug("Bitrise shard matrix written to \(outputPath.pathString)")
    }

    private func writeShardMatrixJSON(shardPlan: Components.Schemas.ShardPlan) async throws {
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
