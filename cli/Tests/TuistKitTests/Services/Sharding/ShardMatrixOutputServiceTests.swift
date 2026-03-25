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
    private let subject: ShardMatrixOutputService
    private let fileSystem = FileSystem()
    private let ciController = MockCIControlling()

    init() {
        subject = ShardMatrixOutputService(fileSystem: fileSystem, ciController: ciController)
    }

    @Test(.inTemporaryDirectory)
    func output_github_writesMatrixToGitHubOutput() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        try await fileSystem.writeText("", at: githubOutputPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))

        try await Environment.$current.withValue(Environment(variables: ["GITHUB_OUTPUT": githubOutputPath.pathString])) {
            try await subject.output(.test(shardCount: 3))
        }

        let content = try await fileSystem.readTextFile(at: githubOutputPath)
        #expect(content == "matrix={\"shard\":[0, 1, 2]}\n")
    }

    @Test(.inTemporaryDirectory)
    func output_gitlab_writesChildPipelineYML() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(.test(provider: .gitlab))

        try await subject.output(.test(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-child-pipeline.yml")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content == """
            shard-0:
              extends: .tuist-shard
              variables:
                TUIST_SHARD_INDEX: "0"

            shard-1:
              extends: .tuist-shard
              variables:
                TUIST_SHARD_INDEX: "1"


            """)
    }

    @Test(.inTemporaryDirectory)
    func output_circleci_writesContinuationJSON() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(.test(provider: .circleci))

        try await subject.output(.test(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-continuation.json")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content == """
            {
              "shard-count" : 2,
              "shard-indices" : "0,1"
            }
            """)
    }

    @Test(.inTemporaryDirectory)
    func output_buildkite_writesPipelineYML() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(.test(provider: .buildkite))

        try await subject.output(.test(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-pipeline.yml")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content == """
            steps:
              - label: "Shard #0"
                env:
                  TUIST_SHARD_INDEX: "0"

              - label: "Shard #1"
                env:
                  TUIST_SHARD_INDEX: "1"


            """)
    }

    @Test(.inTemporaryDirectory)
    func output_codemagic_writesToCMEnv() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let cmEnvPath = temporaryDirectory.appending(component: "CM_ENV")
        try await fileSystem.writeText("", at: cmEnvPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .codemagic))

        try await Environment.$current.withValue(Environment(variables: ["CM_ENV": cmEnvPath.pathString])) {
            try await subject.output(.test(shardCount: 2))
        }

        let content = try await fileSystem.readTextFile(at: cmEnvPath)
        #expect(content == "TUIST_SHARD_MATRIX={\"shard\":[0, 1]}\nTUIST_SHARD_COUNT=2\n")
    }

    @Test(.inTemporaryDirectory)
    func output_bitrise_writesToDeployDir() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let deployDir = temporaryDirectory.appending(component: "deploy")
        try await fileSystem.makeDirectory(at: deployDir)

        given(ciController).ciInfo().willReturn(.test(provider: .bitrise))

        try await Environment.$current.withValue(Environment(variables: ["BITRISE_DEPLOY_DIR": deployDir.pathString])) {
            try await subject.output(.test(shardCount: 2))
        }

        let outputPath = deployDir.appending(component: ".tuist-shard-matrix.json")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content == "{\"shard\":[0, 1],\"shard_count\":2}")
    }

    @Test(.inTemporaryDirectory)
    func output_noCI_writesFallbackJSON() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(ciController).ciInfo().willReturn(nil)

        try await subject.output(.test(shardCount: 2))

        let outputPath = temporaryDirectory.appending(component: ".tuist-shard-matrix.json")
        let content = try await fileSystem.readTextFile(at: outputPath)
        #expect(content == """
            {
              "id" : "test-id",
              "reference" : "test-ref",
              "shard_count" : 2,
              "shards" : [
                {
                  "estimated_duration_ms" : 1000,
                  "index" : 0,
                  "test_targets" : [
                    "Target0"
                  ]
                },
                {
                  "estimated_duration_ms" : 1000,
                  "index" : 1,
                  "test_targets" : [
                    "Target1"
                  ]
                }
              ]
            }
            """)
    }
}

fileprivate extension Components.Schemas.ShardPlan {
    static func test(shardCount: Int = 3) -> Self {
        Components.Schemas.ShardPlan(
            id: "test-id",
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
}
