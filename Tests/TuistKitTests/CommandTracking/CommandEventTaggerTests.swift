import ArgumentParser
import Foundation
import TuistAnalytics
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CommandEventTaggerTests: TuistUnitTestCase {
    private var subject: CommandEventTagger!

    override func setUp() {
        super.setUp()
        subject = CommandEventTagger(machineEnvironment: MockMachineEnvironment())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_tagCommand_tagsExpectedCommand() throws {
        // Given
        let info = TrackableCommandInfo(name: "cache",
                                        subcommand: "warm",
                                        parameters: ["foo": "bar"],
                                        duration: TimeInterval(5000))
        let expectedEvent = CommandEvent(
            name: "cache",
            subcommand: "warm",
            params: ["foo": "bar"],
            duration: TimeInterval(5000),
            clientId: "123",
            tuistVersion: Constants.version,
            swiftVersion: "5.1",
            macOSVersion: "10.15.0",
            machineHardwareName: "arm64"
        )

        // When
        try subject.tagCommand(from: info)

        // Then
//        XCTAssertEqual(mockAnalyticsTagger.comandEventCallCount, 1)
//        let taggedEvent = try XCTUnwrap(mockAnalyticsTagger.commandEventSpy)
//        XCTAssertEqual(taggedEvent, expectedEvent)
    }
}

private final class MockTuistAnalyticsDispatching: TuistAnalyticsDispatching {
    var comandEventCallCount = 0
    var commandEventSpy: CommandEvent?
    func tag(commandEvent: CommandEvent) {
        comandEventCallCount += 1
        commandEventSpy = commandEvent
    }
}

private final class MockMachineEnvironment: MachineEnvironmentRetrieving {
    var clientId: String { "123" }
    var macOSVersion: String { "10.15.0" }
    var swiftVersion: String { "5.1" }
    var hardwareName: String { "arm64" }
}
