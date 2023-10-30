import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

final class XcodeBuildControllerTests: TuistUnitTestCase {
    var subject: XcodeBuildController!
    var formatter: Formatting!

    override func setUp() {
        super.setUp()
        formatter = Formatter()
        subject = XcodeBuildController(formatter: formatter, environment: Environment.shared)
    }

    override func tearDown() {
        subject = nil
        formatter = nil
        super.tearDown()
    }

    func test_build_without_device_id() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let shouldOutputBeColoured = true
        environment.shouldOutputBeColoured = shouldOutputBeColoured

        var command = ["/usr/bin/xcrun", "xcodebuild", "clean", "build", "-scheme", scheme]
        command.append(contentsOf: target.xcodebuildArguments)
        system.succeedCommand((try formatter.formatterExecutable()).compilation ?? [])
        system.succeedCommand(command, output: "output")

        // When
        let events = try subject.build(target, scheme: scheme, destination: nil, rosetta: false, clean: true, arguments: [])

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_build_without_device_id_but_arch() async throws {
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
        let events = try subject.build(target, scheme: scheme, destination: nil, rosetta: true, clean: true, arguments: [])

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_build_with_device_id() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let shouldOutputBeColoured = true
        environment.shouldOutputBeColoured = shouldOutputBeColoured

        var command = ["/usr/bin/xcrun", "xcodebuild", "clean", "build", "-scheme", scheme]
        command.append(contentsOf: target.xcodebuildArguments)
        command.append(contentsOf: ["-destination", "id=this_is_a_udid"])
        system.succeedCommand((try formatter.formatterExecutable()).compilation ?? [])
        system.succeedCommand(command, output: "output")

        // When
        let events = try subject.build(
            target,
            scheme: scheme,
            destination: .device("this_is_a_udid"),
            rosetta: false,
            clean: true,
            arguments: []
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_build_with_device_id_and_arch() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let shouldOutputBeColoured = true
        environment.shouldOutputBeColoured = shouldOutputBeColoured

        var command = ["/usr/bin/xcrun", "xcodebuild", "clean", "build", "-scheme", scheme]
        command.append(contentsOf: target.xcodebuildArguments)
        command.append(contentsOf: ["-destination", "id=this_is_a_udid,arch=x86_64"])
        system.succeedCommand(command, output: "output")

        // When
        let events = try subject.build(
            target,
            scheme: scheme,
            destination: .device("this_is_a_udid"),
            rosetta: true,
            clean: true,
            arguments: []
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_test_when_device() async throws {
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
        system.succeedCommand((try formatter.formatterExecutable()).compilation ?? [])
        system.succeedCommand(command, output: "output")

        // When
        let events = try subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .device("device-id"),
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_test_when_device_arch() async throws {
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
        command.append(contentsOf: ["-destination", "id=device-id,arch=x86_64"])

        system.succeedCommand(command, output: "output")

        // When
        let events = subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .device("device-id"),
            rosetta: true,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_test_when_mac() async throws {
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
        command.append(contentsOf: ["-destination", "platform=macOS,arch=x86_64"])

        system.succeedCommand((try formatter.formatterExecutable()).compilation ?? [])
        system.succeedCommand(command, output: "output")
        developerEnvironment.stubbedArchitecture = .x8664

        // When
        let events = try subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_test_with_derived_data() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let derivedDataPath = try temporaryPath()

        var command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "clean",
            "test",
            "-scheme",
            scheme,
        ]
        command.append(contentsOf: target.xcodebuildArguments)
        command.append(contentsOf: ["-destination", "platform=macOS,arch=x86_64"])
        command.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])

        system.succeedCommand((try formatter.formatterExecutable()).compilation ?? [])
        system.succeedCommand(command, output: "output")
        developerEnvironment.stubbedArchitecture = .x8664

        // When
        let events = try subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            rosetta: false,
            derivedDataPath: derivedDataPath,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }

    func test_test_with_result_bundle_path() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let resultBundlePath = try temporaryPath()

        var command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "clean",
            "test",
            "-scheme",
            scheme,
        ]
        command.append(contentsOf: target.xcodebuildArguments)
        command.append(contentsOf: ["-destination", "platform=macOS,arch=x86_64"])
        command.append(contentsOf: ["-resultBundlePath", resultBundlePath.pathString])

        system.succeedCommand((try formatter.formatterExecutable()).compilation ?? [])
        system.succeedCommand(command, output: "output")
        developerEnvironment.stubbedArchitecture = .x8664

        // When
        let events = try subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: resultBundlePath,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil
        )

        let result = try await events.toArray()
        XCTAssertEqual(result, [.standardOutput(XcodeBuildOutput(raw: "output"))])
    }
}

extension AsyncSequence {
    func toArray() async throws -> [Element] {
        var result = [Element]()
        for try await element in self {
            result.append(element)
        }
        return result
    }
}
