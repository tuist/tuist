import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

final class XcodeBuildControllerTests: TuistUnitTestCase {
    var subject: XcodeBuildController!

    override func setUp() {
        super.setUp()
        subject = XcodeBuildController()
    }

    override func tearDown() {
        super.tearDown()
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

        // When
        let events = subject.build(target, scheme: scheme, clean: true, arguments: [])
            .toBlocking()
            .materialize()

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput(XcodeBuildOutput(raw: "output\n"))])
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

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput(XcodeBuildOutput(raw: "output\n"))])
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

        switch events {
        case let .completed(output):
            XCTAssertEqual(output, [.standardOutput(XcodeBuildOutput(raw: "output\n"))])
        case .failed:
            XCTFail("The command was not expected to fail")
        }
    }
}
