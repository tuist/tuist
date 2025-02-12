import ArgumentParser
import Foundation
import Mockable
import Path
import TuistAnalytics
import TuistCore
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CommandEventFactoryTests: TuistUnitTestCase {
    private var subject: CommandEventFactory!
    private var machineEnvironment: MachineEnvironmentRetrieving!
    private var gitController: MockGitControlling!

    override func setUp() {
        super.setUp()
        machineEnvironment = MockMachineEnvironment()
        gitController = MockGitControlling()

        given(swiftVersionProvider)
            .swiftVersion()
            .willReturn("5.1")

        subject = CommandEventFactory(
            machineEnvironment: machineEnvironment,
            gitController: gitController
        )
    }

    override func tearDown() {
        subject = nil
        machineEnvironment = nil
        gitController = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_tagCommand_tagsExpectedCommand() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project")
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
            resultBundlePath: nil
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
            resultBundlePath: nil
        )

        given(gitController)
            .currentCommitSHA(workingDirectory: .value(path))
            .willReturn("commit-sha")

        given(gitController)
            .hasUrlOrigin(workingDirectory: .value(path))
            .willReturn(true)

        given(gitController)
            .urlOrigin(workingDirectory: .value(path))
            .willReturn("https://github.com/tuist/tuist")

        given(gitController)
            .ref(environment: .any)
            .willReturn("github-ref")

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .hasCurrentBranchCommits(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .currentBranch(workingDirectory: .any)
            .willReturn("main")

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        XCTAssertEqual(event.name, expectedEvent.name)
        XCTAssertEqual(event.subcommand, expectedEvent.subcommand)
        XCTAssertEqual(event.durationInMs, expectedEvent.durationInMs)
        XCTAssertEqual(event.clientId, expectedEvent.clientId)
        XCTAssertEqual(event.tuistVersion, expectedEvent.tuistVersion)
        XCTAssertEqual(event.swiftVersion, expectedEvent.swiftVersion)
        XCTAssertEqual(event.macOSVersion, expectedEvent.macOSVersion)
        XCTAssertEqual(event.machineHardwareName, expectedEvent.machineHardwareName)
        XCTAssertEqual(event.isCI, expectedEvent.isCI)
        XCTAssertEqual(event.gitCommitSHA, expectedEvent.gitCommitSHA)
        XCTAssertEqual(event.gitRemoteURLOrigin, expectedEvent.gitRemoteURLOrigin)
        XCTAssertEqual(event.gitRef, expectedEvent.gitRef)
        XCTAssertBetterEqual(
            event.graph,
            expectedEvent.graph
        )
    }

    func test_make_when_is_not_in_git_repository() throws {
        // Given
        let path = try temporaryPath()
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
            resultBundlePath: nil
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .ref(environment: .any)
            .willReturn(nil)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        XCTAssertEqual(event.gitCommitSHA, nil)
        XCTAssertEqual(event.gitRemoteURLOrigin, nil)
        XCTAssertEqual(event.gitRef, nil)
    }

    func test_make_when_is_in_git_repository_and_branch_has_no_commits_and_no_remote_url_origin() throws {
        // Given
        let path = try temporaryPath()
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
            resultBundlePath: nil
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
            .ref(environment: .any)
            .willReturn(nil)

        given(gitController)
            .currentBranch(workingDirectory: .any)
            .willReturn(nil)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        XCTAssertEqual(event.gitCommitSHA, "commit-sha")
        XCTAssertEqual(event.gitRemoteURLOrigin, nil)
        XCTAssertEqual(event.gitRef, nil)
    }

    func test_make_when_is_in_git_repository_and_branch_has_commits_and_no_remote_url_origin() throws {
        // Given
        let path = try temporaryPath()
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
            resultBundlePath: nil
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .hasCurrentBranchCommits(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .ref(environment: .any)
            .willReturn(nil)

        given(gitController)
            .hasUrlOrigin(workingDirectory: .value(path))
            .willReturn(false)

        given(gitController)
            .currentBranch(workingDirectory: .any)
            .willReturn(nil)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        XCTAssertEqual(event.gitCommitSHA, nil)
        XCTAssertEqual(event.gitRemoteURLOrigin, nil)
        XCTAssertEqual(event.gitRef, nil)
    }
}

private final class MockMachineEnvironment: MachineEnvironmentRetrieving {
    var clientId: String { "123" }
    var macOSVersion: String { "10.15.0" }
    var swiftVersion: String { "5.1" }
    var hardwareName: String { "arm64" }
    var isCI: Bool { false }
}
