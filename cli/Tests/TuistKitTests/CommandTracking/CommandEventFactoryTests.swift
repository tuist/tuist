import ArgumentParser
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistGit
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct CommandEventFactoryTests {
    private var subject: CommandEventFactory!
    private var machineEnvironment: MachineEnvironmentRetrieving!
    private var gitController: MockGitControlling!

    init() throws {
        machineEnvironment = MockMachineEnvironment()
        gitController = MockGitControlling()

        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.1")

        subject = CommandEventFactory(
            machineEnvironment: machineEnvironment,
            gitController: gitController
        )
    }

    // MARK: - Tests

    @Test(.withMockedSwiftVersionProvider, .inTemporaryDirectory) func tagCommand_tagsExpectedCommand() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "Project")
        let ranAt = Date()
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            status: .failure("Failed!"),
            graph: .test(
                name: "Graph",
                path: path,
                projects: [
                    projectPath: .test(
                        path: projectPath,
                        targets: [
                            .test(
                                name: "A"
                            ),
                            .test(
                                name: "B"
                            ),
                            .test(
                                name: "C"
                            ),
                            .test(
                                name: "ATests"
                            ),
                            .test(
                                name: "BTests"
                            ),
                            .test(
                                name: "CTests"
                            ),
                        ]
                    ),
                ]
            ),
            graphBinaryBuildDuration: 1000,
            binaryCacheItems: [
                projectPath: [
                    "A": .test(
                        hash: "hash-a",
                        source: .local
                    ),
                    "B": .test(
                        hash: "hash-b",
                        source: .remote
                    ),
                    "C": .test(
                        hash: "hash-c",
                        source: .miss
                    ),
                ],
            ],
            selectiveTestingCacheItems: [
                projectPath: [
                    "ATests": .test(
                        hash: "hash-a-tests",
                        source: .local
                    ),
                    "BTests": .test(
                        hash: "hash-b-tests",
                        source: .remote
                    ),
                    "CTests": .test(
                        hash: "hash-c-tests",
                        source: .miss
                    ),
                ],
            ],
            targetContentHashSubhashes: [
                "hash-a": .test(
                    sources: "sources-hash-a",
                    dependencies: "deps-hash-a"
                ),
                "hash-b": .test(
                    sources: "sources-hash-b",
                    resources: "resources-hash-b"
                ),
            ],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: ranAt,
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: "https://cache.tuist.dev"
        )
        let expectedEvent = CommandEvent(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            clientId: "123",
            tuistVersion: Constants.version,
            swiftVersion: "5.1",
            macOSVersion: "10.15.0",
            machineHardwareName: "arm64",
            isCI: false,
            status: .failure("Failed!"),
            gitCommitSHA: "commit-sha",
            gitRef: "github-ref",
            gitRemoteURLOrigin: "https://github.com/tuist/tuist",
            gitBranch: "main",
            graph: RunGraph(
                name: "Graph",
                projects: [
                    RunProject(
                        name: "Project",
                        path: try RelativePath(validating: "Project"),
                        targets: [
                            .test(
                                name: "A",
                                product: .app,
                                bundleId: "io.tuist.A",
                                productName: "A",
                                destinations: [.iPhone, .iPad],
                                binaryCacheMetadata: RunCacheTargetMetadata(
                                    hash: "hash-a",
                                    hit: .local,
                                    subhashes: .test(
                                        sources: "sources-hash-a",
                                        dependencies: "deps-hash-a"
                                    )
                                ),
                                selectiveTestingMetdata: nil
                            ),
                            .test(
                                name: "ATests",
                                product: .app,
                                bundleId: "io.tuist.ATests",
                                productName: "ATests",
                                destinations: [.iPhone, .iPad],
                                binaryCacheMetadata: nil,
                                selectiveTestingMetdata: RunCacheTargetMetadata(
                                    hash: "hash-a-tests",
                                    hit: .local
                                )
                            ),
                            .test(
                                name: "B",
                                product: .app,
                                bundleId: "io.tuist.B",
                                productName: "B",
                                destinations: [.iPhone, .iPad],
                                binaryCacheMetadata: RunCacheTargetMetadata(
                                    hash: "hash-b",
                                    hit: .remote,
                                    subhashes: .test(
                                        sources: "sources-hash-b",
                                        resources: "resources-hash-b"
                                    )
                                ),
                                selectiveTestingMetdata: nil
                            ),
                            .test(
                                name: "BTests",
                                product: .app,
                                bundleId: "io.tuist.BTests",
                                productName: "BTests",
                                destinations: [.iPhone, .iPad],
                                binaryCacheMetadata: nil,
                                selectiveTestingMetdata: RunCacheTargetMetadata(
                                    hash: "hash-b-tests",
                                    hit: .remote
                                )
                            ),
                            .test(
                                name: "C",
                                product: .app,
                                bundleId: "io.tuist.C",
                                productName: "C",
                                destinations: [.iPhone, .iPad],
                                binaryCacheMetadata: RunCacheTargetMetadata(
                                    hash: "hash-c",
                                    hit: .miss
                                ),
                                selectiveTestingMetdata: nil
                            ),
                            .test(
                                name: "CTests",
                                product: .app,
                                bundleId: "io.tuist.CTests",
                                productName: "CTests",
                                destinations: [.iPhone, .iPad],
                                binaryCacheMetadata: nil,
                                selectiveTestingMetdata: RunCacheTargetMetadata(
                                    hash: "hash-c-tests",
                                    hit: .miss
                                )
                            ),
                        ]
                    ),
                ],
                binaryBuildDuration: 1000
            ),
            previewId: nil,
            resultBundlePath: nil,
            ranAt: ranAt,
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: "https://cache.tuist.dev"
        )

        given(gitController)
            .currentCommitSHA(workingDirectory: .value(path))
            .willReturn("commit-sha")

        given(gitController)
            .hasUrlOrigin(workingDirectory: .value(path))
            .willReturn(true)

        given(gitController)
            .gitInfo(workingDirectory: .value(path))
            .willReturn(
                .test(
                    ref: "github-ref",
                    branch: "main",
                    sha: "commit-sha",
                    remoteURLOrigin: "https://github.com/tuist/tuist"
                )
            )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .hasCurrentBranchCommits(workingDirectory: .any)
            .willReturn(true)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        #expect(event.name == expectedEvent.name)
        #expect(event.subcommand == expectedEvent.subcommand)
        #expect(event.durationInMs == expectedEvent.durationInMs)
        #expect(event.clientId == expectedEvent.clientId)
        #expect(event.tuistVersion == expectedEvent.tuistVersion)
        #expect(event.swiftVersion == expectedEvent.swiftVersion)
        #expect(event.macOSVersion == expectedEvent.macOSVersion)
        #expect(event.machineHardwareName == expectedEvent.machineHardwareName)
        #expect(event.isCI == expectedEvent.isCI)
        #expect(event.gitCommitSHA == expectedEvent.gitCommitSHA)
        #expect(event.gitRemoteURLOrigin == expectedEvent.gitRemoteURLOrigin)
        #expect(event.gitRef == expectedEvent.gitRef)
        #expect(event.cacheEndpoint == expectedEvent.cacheEndpoint)

        #expect(
            event.graph ==
                expectedEvent.graph
        )
    }

    @Test(.withMockedSwiftVersionProvider, .inTemporaryDirectory) func make_when_is_not_in_git_repository() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            status: .failure("Failed!"),
            graph: nil,
            graphBinaryBuildDuration: 1000,
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            targetContentHashSubhashes: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: ""
        )

        given(gitController)
            .gitInfo(workingDirectory: .value(path))
            .willReturn(.test())

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        #expect(event.gitCommitSHA == nil)
        #expect(event.gitRemoteURLOrigin == nil)
        #expect(event.gitRef == nil)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory
    ) func make_when_is_in_git_repository_and_branch_has_no_commits_and_no_remote_url_origin() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            status: .failure("Failed!"),
            graph: nil,
            graphBinaryBuildDuration: 1000,
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            targetContentHashSubhashes: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: ""
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .currentCommitSHA(workingDirectory: .value(path))
            .willReturn("commit-sha")

        given(gitController)
            .hasCurrentBranchCommits(workingDirectory: .value(path))
            .willReturn(true)

        given(gitController)
            .hasUrlOrigin(workingDirectory: .value(path))
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .value(path))
            .willReturn(.test(ref: nil, branch: nil, sha: "commit-sha"))

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        #expect(event.gitCommitSHA == "commit-sha")
        #expect(event.gitRemoteURLOrigin == nil)
        #expect(event.gitRef == nil)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory
    ) func make_when_is_in_git_repository_and_branch_has_commits_and_no_remote_url_origin() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            status: .failure("Failed!"),
            graph: nil,
            graphBinaryBuildDuration: 1000,
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            targetContentHashSubhashes: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: ""
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .hasCurrentBranchCommits(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .value(path))
            .willReturn(.test())

        given(gitController)
            .hasUrlOrigin(workingDirectory: .value(path))
            .willReturn(false)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        #expect(event.gitCommitSHA == nil)
        #expect(event.gitRemoteURLOrigin == nil)
        #expect(event.gitRef == nil)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory
    ) func make_includes_cache_endpoint_from_trackable_command_info() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let cacheEndpoint = "https://eu.cache.tuist.dev"
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "generate",
            subcommand: nil,
            commandArguments: ["generate"],
            durationInMs: 1000,
            status: .success,
            graph: nil,
            graphBinaryBuildDuration: nil,
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            targetContentHashSubhashes: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: cacheEndpoint
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .value(path))
            .willReturn(.test())

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        #expect(event.cacheEndpoint == cacheEndpoint)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory
    ) func make_includes_empty_cache_endpoint_when_not_set() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "generate",
            subcommand: nil,
            commandArguments: ["generate"],
            durationInMs: 1000,
            status: .success,
            graph: nil,
            graphBinaryBuildDuration: nil,
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            targetContentHashSubhashes: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil,
            testRunId: nil,
            cacheEndpoint: ""
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .value(path))
            .willReturn(.test())

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        #expect(event.cacheEndpoint == "")
    }
}

private final class MockMachineEnvironment: MachineEnvironmentRetrieving {
    var clientId: String { "123" }
    var macOSVersion: String { "10.15.0" }
    var swiftVersion: String { "5.1" }
    var hardwareName: String { "arm64" }
    var isCI: Bool { false }
    func modelIdentifier() -> String? {
        nil
    }
}
