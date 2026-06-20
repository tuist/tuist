import FileSystem
import Foundation
import Mockable
import Path
import SwiftyJSON
import Testing
import TuistCI
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer

@testable import TuistKit

struct ShardMatrixOutputServiceTests {
    @Test(.withMockedEnvironment())
    func output_github_writesMatrixToGitHubOutput() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()
        let githubOutputPath = cwd.appending(component: "github_output")
        try await fixture.fileSystem.writeText("", at: githubOutputPath, encoding: .utf8)

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString

        try await fixture.subject.output(.test(shardCount: 3))

        let content = try await fixture.fileSystem.readTextFile(at: githubOutputPath)
        #expect(content == "matrix={\"shard\":[0, 1, 2]}\n")
    }

    @Test(.withMockedEnvironment())
    func output_github_writesEmptyMatrixWhenNoShards() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()
        let githubOutputPath = cwd.appending(component: "github_output_empty")
        try await fixture.fileSystem.writeText("", at: githubOutputPath, encoding: .utf8)

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString

        try await fixture.subject.output(.test(shardCount: 0))

        let content = try await fixture.fileSystem.readTextFile(at: githubOutputPath)
        let matrixValue = try #require(content.split(separator: "=", maxSplits: 1).last.map(String.init))
        let json = try JSON(data: Data(matrixValue.utf8))
        #expect(json["shard"].arrayValue.isEmpty)
    }

    @Test(.withMockedEnvironment())
    func output_gitlab_writesChildPipelineYML() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .gitlab))

        try await fixture.subject.output(.test(shardCount: 2))

        let content = try await fixture.fileSystem.readTextFile(at: cwd.appending(component: ".tuist-shard-child-pipeline.yml"))
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

    @Test(.withMockedEnvironment())
    func output_circleci_writesContinuationJSON() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .circleci))

        try await fixture.subject.output(.test(shardCount: 2))

        let content = try await fixture.fileSystem.readTextFile(at: cwd.appending(component: ".tuist-shard-continuation.json"))
        #expect(content == """
        {
          "shard-count" : 2,
          "shard-indices" : "0,1"
        }
        """)
    }

    @Test(.withMockedEnvironment())
    func output_buildkite_writesPipelineYML() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .buildkite))

        try await fixture.subject.output(.test(shardCount: 2))

        let content = try await fixture.fileSystem.readTextFile(at: cwd.appending(component: ".tuist-shard-pipeline.yml"))
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

    @Test(.withMockedEnvironment())
    func output_codemagic_writesToCMEnv() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()
        let cmEnvPath = cwd.appending(component: "CM_ENV")
        try await fixture.fileSystem.writeText("", at: cmEnvPath, encoding: .utf8)

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .codemagic))
        Environment.mocked?.variables["CM_ENV"] = cmEnvPath.pathString

        try await fixture.subject.output(.test(shardCount: 2))

        let content = try await fixture.fileSystem.readTextFile(at: cmEnvPath)
        #expect(content == "TUIST_SHARD_MATRIX={\"shard\":[0, 1]}\nTUIST_SHARD_COUNT=2\n")
    }

    @Test(.withMockedEnvironment())
    func output_bitrise_writesToDeployDir() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()
        let deployDir = cwd.appending(component: "deploy")
        try await fixture.fileSystem.makeDirectory(at: deployDir)

        given(fixture.ciController).ciInfo().willReturn(.test(provider: .bitrise))
        Environment.mocked?.variables["BITRISE_DEPLOY_DIR"] = deployDir.pathString

        try await fixture.subject.output(.test(shardCount: 2))

        let content = try await fixture.fileSystem.readTextFile(at: deployDir.appending(component: ".tuist-shard-matrix.json"))
        #expect(content == "{\"shard\":[0, 1],\"shard_count\":2}")
    }

    @Test(.withMockedEnvironment())
    func output_noCI_writesFallbackJSON() async throws {
        let fixture = makeSubject()
        let cwd = try await Environment.current.currentWorkingDirectory()

        given(fixture.ciController).ciInfo().willReturn(nil)

        try await fixture.subject.output(.test(shardCount: 2))

        let content = try await fixture.fileSystem.readTextFile(at: cwd.appending(component: ".tuist-shard-matrix.json"))
        let json = try JSON(data: Data(content.utf8))
        #expect(json["id"].stringValue == "test-id")
        #expect(json["reference"].stringValue == "test-ref")
        #expect(json["shard_count"].intValue == 2)

        let shards = json["shards"].arrayValue
        #expect(shards.map { $0["estimated_duration_ms"].intValue } == [1000, 1000])
        #expect(shards.map { $0["index"].intValue } == [0, 1])
        #expect(shards.map { $0["test_targets"].arrayValue.map(\.stringValue) } == [["Target0"], ["Target1"]])
    }

    private func makeSubject() -> (
        subject: ShardMatrixOutputService,
        fileSystem: FileSystem,
        ciController: MockCIControlling
    ) {
        let fileSystem = FileSystem()
        let ciController = MockCIControlling()
        return (
            subject: ShardMatrixOutputService(fileSystem: fileSystem, ciController: ciController),
            fileSystem: fileSystem,
            ciController: ciController
        )
    }
}

extension Components.Schemas.ShardPlan {
    fileprivate static func test(shardCount: Int = 3) -> Self {
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
