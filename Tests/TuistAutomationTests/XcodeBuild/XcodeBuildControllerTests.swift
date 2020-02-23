import Basic
import Foundation
import RxBlocking
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

final class XcodeBuildTargetTests: TuistUnitTestCase {
    func test_xcodebuildArguments_returns_the_right_arguments_when_project() throws {
        // Given
        let path = try temporaryPath()
        let xcodeprojPath = path.appending(component: "Project.xcodeproj")
        let subject = XcodeBuildTarget.project(xcodeprojPath)

        // When
        let got = subject.xcodebuildArguments

        // Then
        XCTAssertEqual(got, ["-project", xcodeprojPath.pathString])
    }

    func test_xcodebuildArguments_returns_the_right_arguments_when_workspace() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let subject = XcodeBuildTarget.workspace(xcworkspacePath)

        // When
        let got = subject.xcodebuildArguments

        // Then
        XCTAssertEqual(got, ["-workspace", xcworkspacePath.pathString])
    }
}

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

        var command = ["/usr/bin/xcrun", "xcodebuild", "-scheme", scheme]
        command.append(contentsOf: target.xcodebuildArguments)
        command.append(contentsOf: ["build", "clean"])

        system.succeedCommand(command, output: "output")
        var parseCalls: [(String, Bool)] = []
        parser.parseStub = { output, colored in
            parseCalls.append((output, colored))
            return "formated-output"
        }

        // When
        let events = subject.build(target, scheme: scheme, clean: true)
            .toBlocking()
            .materialize()

        // Then
        XCTAssertEqual(parseCalls.count, 1)
        XCTAssertEqual(parseCalls.first?.0, "output")
        XCTAssertEqual(parseCalls.first?.1, shouldOutputBeColoured)

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput("formated-output")])
        case .failed:
            XCTFail("The command was not expected to fail")
        }
    }
}
