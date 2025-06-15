import ArgumentParser
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAnalytics
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

    @Test(.withMockedSwiftVersionProvider, .inTemporaryDirectory) func test_tagCommand_tagsExpectedCommand() throws {
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
            previewId: nil,
            resultBundlePath: nil,
            ranAt: ranAt,
            buildRunId: nil
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
                            RunTarget(
                                name: "A",
                                binaryCacheMetadata: RunCacheTargetMetadata(
                                    hash: "hash-a",
                                    hit: .local
                                ),
                                selectiveTestingMetadata: nil
                            ),
                            RunTarget(
                                name: "ATests",
                                binaryCacheMetadata: nil,
                                selectiveTestingMetadata: RunCacheTargetMetadata(
                                    hash: "hash-a-tests",
                                    hit: .local
                                )
                            ),
                            RunTarget(
                                name: "B",
                                binaryCacheMetadata: RunCacheTargetMetadata(
                                    hash: "hash-b",
                                    hit: .remote
                                ),
                                selectiveTestingMetadata: nil
                            ),
                            RunTarget(
                                name: "BTests",
                                binaryCacheMetadata: nil,
                                selectiveTestingMetadata: RunCacheTargetMetadata(
                                    hash: "hash-b-tests",
                                    hit: .remote
                                )
                            ),
                            RunTarget(
                                name: "C",
                                binaryCacheMetadata: RunCacheTargetMetadata(
                                    hash: "hash-c",
                                    hit: .miss
                                ),
                                selectiveTestingMetadata: nil
                            ),
                            RunTarget(
                                name: "CTests",
                                binaryCacheMetadata: nil,
                                selectiveTestingMetadata: RunCacheTargetMetadata(
                                    hash: "hash-c-tests",
                                    hit: .miss
                                )
                            ),
                        ]
                    ),
                ]
            ),
            previewId: nil,
            resultBundlePath: nil,
            ranAt: ranAt,
            buildRunId: nil
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

        #expect(
            event.graph ==
                expectedEvent.graph
        )
    }

    @Test(.withMockedSwiftVersionProvider, .inTemporaryDirectory) func test_make_when_is_not_in_git_repository() throws {
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
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil
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
    ) func test_make_when_is_in_git_repository_and_branch_has_no_commits_and_no_remote_url_origin() throws {
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
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil
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
    ) func test_make_when_is_in_git_repository_and_branch_has_commits_and_no_remote_url_origin() throws {
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
            binaryCacheItems: [:],
            selectiveTestingCacheItems: [:],
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date(),
            buildRunId: nil
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
