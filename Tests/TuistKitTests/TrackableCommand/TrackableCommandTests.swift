import Foundation
import TuistSupport
import XCTest
import ArgumentParser

@testable import TuistKit
@testable import TuistSupportTesting

final class TrackableCommandTests: TuistUnitTestCase {
    var subject: TrackableCommand!
    var mockCommandEventTagger: MockCommandEventTagging!

    override func setUp() {
        super.setUp()
        mockCommandEventTagger = MockCommandEventTagging()
    }

    override func tearDown() {
        subject = nil
        mockCommandEventTagger = nil
        super.tearDown()
    }

    private func makeSubject(flag: Bool = true) {
        subject = TrackableCommand(command: TestCommand(flag: flag),
                                   commandEventTagger: mockCommandEventTagger,
                                   clock: WallClock())
    }

    func test_whenFlagTrue_callsCommandEventTaggerWithExpectedParameters() throws {
        // Given
        makeSubject(flag: true)
        let expectedParams = ["flag": "true"]
        // When
        try subject.run()
        
        // Then
        XCTAssertEqual(mockCommandEventTagger.tagCommandCallCount, 1)
        let info = try XCTUnwrap(mockCommandEventTagger.infoSpy)
        XCTAssertEqual(info.name, "test")
        XCTAssertTrue(info.duration > 0)
        XCTAssertEqual(info.parameters, expectedParams)
    }

    func test_whenFlagFalse_callsCommandEventTaggerWithExpectedParameters() throws {
        // Given
        makeSubject(flag: false)
        let expectedParams = ["flag": "false"]

        // When
        try subject.run()

        // Then
        XCTAssertEqual(mockCommandEventTagger.tagCommandCallCount, 1)
        let info = try XCTUnwrap(mockCommandEventTagger.infoSpy)
        XCTAssertEqual(info.name, "test")
        XCTAssertTrue(info.duration > 0)
        XCTAssertEqual(info.parameters, expectedParams)
    }
}

final class MockCommandEventTagging: CommandEventTagging {
    var infoSpy: TrackableCommandInfo?
    var tagCommandCallCount = 0
    func tagCommand(from info: TrackableCommandInfo) {
        tagCommandCallCount += 1
        infoSpy = info
    }
}

struct TestCommand: ParsableCommand, HasTrackableParameters {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "test")
    }

    var flag: Bool = false

    static var analyticsDelegate: TrackableParametersDelegate?

    func run() throws {
        TestCommand.analyticsDelegate?.willRun(withParamters: ["flag" : String(flag)])
    }
}
