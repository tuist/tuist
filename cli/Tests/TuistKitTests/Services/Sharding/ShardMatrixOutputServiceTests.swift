import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCI
import TuistEnvironment
import TuistServer

@testable import TuistKit

struct ShardMatrixOutputServiceTests {
    private let fileSystem = FileSystem()
    private let ciController = MockCIControlling()

    private func makeSubject() -> ShardMatrixOutputService {
        ShardMatrixOutputService(fileSystem: fileSystem, ciController: ciController)
    }

    private func makeShardPlan(shardCount: Int = 3) -> Components.Schemas.ShardPlan {
        Components.Schemas.ShardPlan(
            id: UUID().uuidString,
            reference: "test-ref",
            shard_count: shardCount,
            shards: (0 ..< shardCount).map { index in
                Components.Schemas.ShardPlan.shardsPayloadPayload(
                    estimated_duration_ms: 1000,
                    index: index,
                    test_targets: ["Target\(index)"]
                )
            }
        )
    }

    @Test(.inTemporaryDirectory)
    func output_github_writesMatrixToGitHubOutput() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        try await fileSystem.writeText("", at: githubOutputPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))

        try await Environment.$current.withValue(Environment(variables: ["GITHUB_OUTPUT": githubOutputPath.pathString])) {
            try await makeSubject().output(makeShardPlan(shardCount: 3))
        }

        let content = try await fileSystem.readTextFile(at: githubOutputPath)
        #expect(content.contains("matrix="))
        #expect(content.contains("[0, 1, 2]"))
    }

    @Test(.inTemporaryDirectory)
    func output_gitlab_writesChildPipelineYML() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(.test(provider: .gitlab))

        try await makeSubject().output(makeShardPlan(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-child-pipeline.yml")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content.contains("shard-0:"))
        #expect(content.contains("shard-1:"))
        #expect(content.contains("extends: .tuist-shard"))
        #expect(content.contains("TUIST_SHARD_INDEX: \"0\""))
        #expect(content.contains("TUIST_SHARD_INDEX: \"1\""))
    }

    @Test(.inTemporaryDirectory)
    func output_circleci_writesContinuationJSON() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(.test(provider: .circleci))

        try await makeSubject().output(makeShardPlan(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-continuation.json")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content.contains("shard-indices"))
        #expect(content.contains("0,1"))
        #expect(content.contains("shard-count"))
    }

    @Test(.inTemporaryDirectory)
    func output_buildkite_writesPipelineYML() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(.test(provider: .buildkite))

        try await makeSubject().output(makeShardPlan(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-pipeline.yml")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content.contains("steps:"))
        #expect(content.contains("Shard #0"))
        #expect(content.contains("Shard #1"))
        #expect(content.contains("TUIST_SHARD_INDEX: \"0\""))
    }

    @Test(.inTemporaryDirectory)
    func output_codemagic_writesToCMEnv() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let cmEnvPath = temporaryDirectory.appending(component: "CM_ENV")
        try await fileSystem.writeText("", at: cmEnvPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .codemagic))

        try await Environment.$current.withValue(Environment(variables: ["CM_ENV": cmEnvPath.pathString])) {
            try await makeSubject().output(makeShardPlan(shardCount: 2))
        }

        let content = try await fileSystem.readTextFile(at: cmEnvPath)
        #expect(content.contains("TUIST_SHARD_MATRIX="))
        #expect(content.contains("TUIST_SHARD_COUNT=2"))
    }

    @Test(.inTemporaryDirectory)
    func output_bitrise_writesToDeployDir() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let deployDir = temporaryDirectory.appending(component: "deploy")
        try await fileSystem.makeDirectory(at: deployDir)

        given(ciController).ciInfo().willReturn(.test(provider: .bitrise))

        try await Environment.$current.withValue(Environment(variables: ["BITRISE_DEPLOY_DIR": deployDir.pathString])) {
            try await makeSubject().output(makeShardPlan(shardCount: 2))
        }

        let outputPath = deployDir.appending(component: ".tuist-shard-matrix.json")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content.contains("\"shard\""))
        #expect(content.contains("\"shard_count\""))
    }

    @Test(.inTemporaryDirectory)
    func output_noCI_writesFallbackJSON() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(nil)

        try await makeSubject().output(makeShardPlan(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-matrix.json")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content.contains("shard_count"))
        #expect(content.contains("test_targets"))
    }
}
