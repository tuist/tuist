import ArgumentParser
import Foundation
import TuistAnalytics
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CommandEventFactoryTests: TuistUnitTestCase {
    private var subject: CommandEventFactory!
    private var mockMachineEnv: MachineEnvironmentRetrieving!

    override func setUp() {
        super.setUp()
        mockMachineEnv = MockMachineEnvironment()
        subject = CommandEventFactory(machineEnvironment: mockMachineEnv)
    }

    override func tearDown() {
        subject = nil
        mockMachineEnv = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_tagCommand_tagsExpectedCommand() throws {
        // Given
        let info = TrackableCommandInfo(
            name: "cache",
            subcommand: "warm",
            parameters: ["foo": "bar"],
            durationInMs: 5000
        )
        let expectedEvent = CommandEvent(
            name: "cache",
            subcommand: "warm",
            params: ["foo": "bar"],
            durationInMs: 5000,
            clientId: "123",
            tuistVersion: Constants.version,
            swiftVersion: "5.1",
            macOSVersion: "10.15.0",
            machineHardwareName: "arm64",
            isCI: false
        )

        // When
        let event = subject.make(from: info)

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
