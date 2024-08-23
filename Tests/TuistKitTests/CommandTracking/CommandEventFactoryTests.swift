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
    private var gitHandler: MockGitHandling!
    private var gitRefReader: MockGitRefReading!

    override func setUp() {
        super.setUp()
        machineEnvironment = MockMachineEnvironment()
        gitHandler = MockGitHandling()
        gitRefReader = MockGitRefReading()
        subject = CommandEventFactory(
            environment: environment,
            machineEnvironment: machineEnvironment,
            gitHandler: gitHandler,
            gitRefReader: gitRefReader
        )
    }

    override func tearDown() {
        subject = nil
        machineEnvironment = nil
        gitHandler = nil
        gitRefReader = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_tagCommand_tagsExpectedCommand() throws {
        // Given
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
            commitSHA: "commit-sha",
            gitRef: "github-ref",
            gitRemoteURLOrigin: "https://github.com/tuist/tuist"
        )
        given(gitHandler)
            .currentCommitSHA()
            .willReturn("commit-sha")

        given(gitHandler)
            .urlOrigin()
            .willReturn("https://github.com/tuist/tuist")

        given(gitRefReader)
            .read()
            .willReturn("github-ref")

        // When
        let event = try subject.make(from: info)

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
    }
}

private final class MockMachineEnvironment: MachineEnvironmentRetrieving {
    var clientId: String { "123" }
    var macOSVersion: String { "10.15.0" }
    var swiftVersion: String { "5.1" }
    var hardwareName: String { "arm64" }
    var isCI: Bool { false }
}
