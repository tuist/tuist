import Command
import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

final class MockFormatter: Formatting {
    func format(_ line: String) -> String? {
        line
    }
}

final class XcodeBuildControllerTests: TuistUnitTestCase {
    var subject: XcodeBuildController!
    var formatter: Formatting!
    var commandRunner: MockCommandRunning!

    override func setUp() {
        super.setUp()
        formatter = MockFormatter()
        commandRunner = MockCommandRunning()
        subject = XcodeBuildController(
            formatter: formatter,
            environment: environment,
            commandRunner: commandRunner
        )
    }

    override func tearDown() {
        subject = nil
        formatter = nil
        commandRunner = nil
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
        system.succeedCommand(command, output: "output")

        // When
        try await subject.build(
            target,
            scheme: scheme,
            destination: nil,
            rosetta: false,
            derivedDataPath: nil,
            clean: true,
            arguments: [],
            passthroughXcodeBuildArguments: []
        )
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
        try await subject.build(
            target,
            scheme: scheme,
            destination: nil,
            rosetta: true,
            derivedDataPath: nil,
            clean: true,
            arguments: [],
            passthroughXcodeBuildArguments: []
        )
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
        system.succeedCommand(command, output: "output")

        // When
        try await subject.build(
            target,
            scheme: scheme,
            destination: .device("this_is_a_udid"),
            rosetta: false,
            derivedDataPath: nil,
            clean: true,
            arguments: [],
            passthroughXcodeBuildArguments: []
        )
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
        try await subject.build(
            target,
            scheme: scheme,
            destination: .device("this_is_a_udid"),
            rosetta: true,
            derivedDataPath: nil,
            clean: true,
            arguments: [],
            passthroughXcodeBuildArguments: []
        )
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
        system.succeedCommand(command, output: "output")

        // When
        try await subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .device("device-id"),
            action: .test,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
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
        try await subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .device("device-id"),
            action: .test,
            rosetta: true,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
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

        system.succeedCommand(command, output: "output")
        developerEnvironment.stubbedArchitecture = .x8664

        // When
        try await subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            action: .test,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
    }

    func test_test_when_destination_is_specified_with_passthrough_arguments() async throws {
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
        try await subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: nil,
            action: .test,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: [
                "-destination", "id=device-id",
            ]
        )
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

        system.succeedCommand(command, output: "output")
        developerEnvironment.stubbedArchitecture = .x8664

        // When
        try await subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            action: .test,
            rosetta: false,
            derivedDataPath: derivedDataPath,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
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

        system.succeedCommand(command, output: "output")
        developerEnvironment.stubbedArchitecture = .x8664

        // When
        try await subject.test(
            target,
            scheme: scheme,
            clean: true,
            destination: .mac,
            action: .test,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: resultBundlePath,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
    }

    func test_test_build_only() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"

        var command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "build-for-testing",
            "-scheme",
            scheme,
        ]

        command.append(contentsOf: target.xcodebuildArguments)

        system.succeedCommand(command, output: "output")

        // When
        try await subject.test(
            target,
            scheme: scheme,
            clean: false,
            destination: nil,
            action: .build,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
    }

    func test_test_only() async throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"

        var command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "test-without-building",
            "-scheme",
            scheme,
        ]

        command.append(contentsOf: target.xcodebuildArguments)

        system.succeedCommand(command, output: "output")

        // When
        try await subject.test(
            target,
            scheme: scheme,
            clean: false,
            destination: nil,
            action: .testWithoutBuilding,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [],
            retryCount: 0,
            testTargets: [],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: []
        )
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
