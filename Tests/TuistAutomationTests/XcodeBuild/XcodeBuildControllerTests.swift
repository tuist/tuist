import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

private final class MockParser: Parsing {
    var parseStub: ((String, Bool) -> String?)?

    func parse(line: String, colored: Bool) -> String? {
        parseStub?(line, colored)
    }
}

final class XcodeBuildControllerTests: TuistUnitTestCase {
    var subject: XcodeBuildController!
    fileprivate var parser: MockParser!

    override func setUp() {
        super.setUp()
        parser = MockParser()
        subject = XcodeBuildController(parser: parser)
    }

    override func tearDown() {
        super.tearDown()
        parser = nil
        subject = nil
    }

    func test_build() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let shouldOutputBeColoured = true
        environment.shouldOutputBeColoured = shouldOutputBeColoured

        var command = ["/usr/bin/xcrun", "xcodebuild", "clean", "build", "-scheme", scheme]
        command.append(contentsOf: target.xcodebuildArguments)

        system.succeedCommand(command, output: "output")
        var parseCalls: [(String, Bool)] = []
        parser.parseStub = { output, colored in
            parseCalls.append((output, colored))
            return "formated-output"
        }

        // When
        let events = subject.build(target, scheme: scheme, clean: true, arguments: [])
            .toBlocking()
            .materialize()

        // Then
        XCTAssertEqual(parseCalls.count, 1)
        XCTAssertEqual(parseCalls.first?.0, "output")
        XCTAssertEqual(parseCalls.first?.1, shouldOutputBeColoured)

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput(XcodeBuildOutput(raw: "output\n", formatted: "formated-output\n"))])
        case .failed:
            XCTFail("The command was not expected to fail")
        }
    }
    
    func test_test_when_device() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let shouldOutputBeColoured = true
        environment.shouldOutputBeColoured = shouldOutputBeColoured
        
        var command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "clean",
            "test",
            "-scheme",
            scheme,
        ]
        command.append(contentsOf: target.xcodebuildArguments)
        command.append(contentsOf: ["-destination", "id=device-id"])

        system.succeedCommand(command, output: "output")
        var parseCalls: [(String, Bool)] = []
        parser.parseStub = { output, colored in
            parseCalls.append((output, colored))
            return "formated-output"
        }

        // When
        let events = subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .device("device-id"),
            arguments: []
        )
            .toBlocking()
            .materialize()

        // Then
        XCTAssertEqual(parseCalls.count, 1)
        XCTAssertEqual(parseCalls.first?.0, "output")
        XCTAssertEqual(parseCalls.first?.1, shouldOutputBeColoured)

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput(XcodeBuildOutput(raw: "output\n", formatted: "formated-output\n"))])
        case .failed:
            XCTFail("The command was not expected to fail")
        }
    }
    
    func test_test_when_mac() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let shouldOutputBeColoured = true
        environment.shouldOutputBeColoured = shouldOutputBeColoured
        
        var command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "clean",
            "test",
            "-scheme",
            scheme,
        ]
        command.append(contentsOf: target.xcodebuildArguments)

        system.succeedCommand(command, output: "output")
        var parseCalls: [(String, Bool)] = []
        parser.parseStub = { output, colored in
            parseCalls.append((output, colored))
            return "formated-output"
        }

        // When
        let events = subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            arguments: []
        )
            .toBlocking()
            .materialize()

        // Then
        XCTAssertEqual(parseCalls.count, 1)
        XCTAssertEqual(parseCalls.first?.0, "output")
        XCTAssertEqual(parseCalls.first?.1, shouldOutputBeColoured)

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput(XcodeBuildOutput(raw: "output\n", formatted: "formated-output\n"))])
        case .failed:
            XCTFail("The command was not expected to fail")
        }
    }
}
