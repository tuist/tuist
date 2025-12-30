import Command
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TSCBasic
import TuistCore
import TuistSupport

@testable import TuistAutomation
@testable import TuistTesting

final class MockFormatter: Formatting {
    func format(_ line: String) -> String? {
        line
    }
}

struct XcodeBuildControllerTests {
    var subject: XcodeBuildController!
    var formatter = MockFormatter()
    var system = MockSystem()
    var commandRunner = MockCommandRunning()

    init() {
        subject = XcodeBuildController(
            formatter: formatter,
            commandRunner: commandRunner,
            system: system
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func build_without_device_id() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)

        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func build_without_device_id_but_arch() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func build_with_device_id() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func build_with_device_id_and_arch() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func when_device() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func when_device_arch() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func when_mac() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)

        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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
        environment.stubbedArchitecture = .x8664

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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func when_destination_is_specified_with_passthrough_arguments() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func with_derived_data() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)

        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let derivedDataPath = temporaryDirectory

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
        mockEnvironment.stubbedArchitecture = .x8664

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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func with_result_bundle_path() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let mockEnvironment = try #require(Environment.mocked)

        let target = XcodeBuildTarget.workspace(xcworkspacePath)
        let scheme = "Scheme"
        let resultBundlePath = temporaryDirectory

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
        mockEnvironment.stubbedArchitecture = .x8664

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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func build_only() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func only() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
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
