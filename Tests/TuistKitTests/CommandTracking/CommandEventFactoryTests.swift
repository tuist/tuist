import ArgumentParser
import Foundation
import MockableTest
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
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            parameters: ["foo": "bar"],
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            status: .failure("Failed!")
        )
        let expectedEvent = CommandEvent(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            params: ["foo": "bar"],
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
            gitRemoteURLOrigin: "https://github.com/tuist/tuist"
        )
        given(gitController)
            .currentCommitSHA(workingDirectory: .value(path))
            .willReturn("commit-sha")

        given(gitController)
            .urlOrigin(workingDirectory: .value(path))
            .willReturn("https://github.com/tuist/tuist")

        given(gitController)
            .ref(environment: .any)
            .willReturn("github-ref")

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        // When
        let event = try subject.make(
            from: info,
            path: path
        )

        // Then
        XCTAssertEqual(event.name, expectedEvent.name)
        XCTAssertEqual(event.subcommand, expectedEvent.subcommand)
        XCTAssertEqual(event.params, expectedEvent.params)
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
    }

    func test_make_when_is_not_in_git_repository() throws {
        // Given
        let path = try temporaryPath()
        let info = TrackableCommandInfo(
            runId: "run-id",
            name: "cache",
            subcommand: "warm",
            parameters: ["foo": "bar"],
            commandArguments: ["cache", "warm"],
            durationInMs: 5000,
            status: .failure("Failed!")
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
}

private final class MockMachineEnvironment: MachineEnvironmentRetrieving {
    var clientId: String { "123" }
    var macOSVersion: String { "10.15.0" }
    var swiftVersion: String { "5.1" }
    var hardwareName: String { "arm64" }
    var isCI: Bool { false }
}
