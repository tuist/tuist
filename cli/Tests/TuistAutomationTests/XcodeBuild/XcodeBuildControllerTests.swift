import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TSCBasic
import TuistCore
import TuistEnvironment
import TuistProcess
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
    var commandRunner = MockCommandRunner()

    init() {
        subject = XcodeBuildController(
            formatter: formatter,
            commandRunner: commandRunner
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
        commandRunner.succeedCommand(command, output: "output")

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
        commandRunner.succeedCommand(command, output: "output")

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
        commandRunner.succeedCommand(command, output: "output")

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
        commandRunner.succeedCommand(command, output: "output")

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
        commandRunner.succeedCommand(command, output: "output")

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
        commandRunner.succeedCommand(command, output: "output")

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

        commandRunner.succeedCommand(command, output: "output")
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

        commandRunner.succeedCommand(command, output: "output")

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

        commandRunner.succeedCommand(command, output: "output")
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

        commandRunner.succeedCommand(command, output: "output")
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

        commandRunner.succeedCommand(command, output: "output")

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

        commandRunner.succeedCommand(command, output: "output")

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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func without_building_with_xctestrun() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let xctestrunPath = temporaryDirectory.appending(component: "Project.xctestrun")
        let target = XcodeBuildTarget.workspace(xcworkspacePath)

        let command = [
            "/usr/bin/xcrun",
            "xcodebuild",
            "test-without-building",
            "-configuration",
            "Debug",
            "-xctestrun",
            xctestrunPath.pathString,
            "-only-testing",
            "ProjectTests",
        ]
        commandRunner.succeedCommand(command, output: "output")

        // When
        try await subject.test(
            target,
            scheme: "Project",
            clean: false,
            destination: nil,
            action: .testWithoutBuilding,
            rosetta: false,
            derivedDataPath: nil,
            resultBundlePath: nil,
            arguments: [.configuration("Debug")],
            retryCount: 0,
            testTargets: [try TestIdentifier(target: "ProjectTests")],
            skipTestTargets: [],
            testPlanConfiguration: nil,
            passthroughXcodeBuildArguments: ["-xctestrun", xctestrunPath.pathString]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_whenWorkspaceHasXcodeCachePackagesXCConfig_passesIt() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let xcconfigPath = XcodeCachePackagesXCConfig.path(xcWorkspacePath: xcworkspacePath)
        try await FileSystem().makeDirectory(at: xcconfigPath.parentDirectory)
        try await FileSystem().writeText("", at: xcconfigPath)
        let arguments = ["build", "-workspace", xcworkspacePath.pathString, "-scheme", "App"]
        commandRunner.succeedCommand(["/usr/bin/xcrun", "xcodebuild"] + arguments)

        // When
        try await subject.run(arguments: arguments)

        // Then
        #expect(commandRunner.env["XCODE_XCCONFIG_FILE"] == xcconfigPath.pathString)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_whenXcodeXCConfigFileIsSet_passesAFileIncludingBoth() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["XCODE_XCCONFIG_FILE"] = "/tmp/Custom.xcconfig"
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let xcconfigPath = XcodeCachePackagesXCConfig.path(xcWorkspacePath: xcworkspacePath)
        try await FileSystem().makeDirectory(at: xcconfigPath.parentDirectory)
        try await FileSystem().writeText("", at: xcconfigPath)
        let arguments = ["build", "-workspace", xcworkspacePath.pathString, "-scheme", "App"]
        commandRunner.succeedCommand(["/usr/bin/xcrun", "xcodebuild"] + arguments)

        // When
        try await subject.run(arguments: arguments)

        // Then
        let passedPath = try #require(commandRunner.env["XCODE_XCCONFIG_FILE"])
        #expect(passedPath != "/tmp/Custom.xcconfig")
        #expect(passedPath != xcconfigPath.pathString)
        #expect(passedPath.hasSuffix("/xcode-cache.xcconfig"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_whenXcodeXCConfigFileIsSetAndWorkspaceHasNoPackagesXCConfig_keepsIt() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["XCODE_XCCONFIG_FILE"] = "/tmp/Custom.xcconfig"
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let arguments = ["build", "-workspace", xcworkspacePath.pathString, "-scheme", "App"]
        commandRunner.succeedCommand(["/usr/bin/xcrun", "xcodebuild"] + arguments)

        // When
        try await subject.run(arguments: arguments)

        // Then
        #expect(commandRunner.env["XCODE_XCCONFIG_FILE"] == "/tmp/Custom.xcconfig")
    }

    /// The package settings come last so their `$(inherited)` extends the user's settings.
    @Test
    func xcconfig_includesThePathsInOrder() throws {
        let user = try Path.AbsolutePath(validating: "/tmp/my configs/Custom.xcconfig")
        let packages = try Path.AbsolutePath(validating: "/repo/App.xcworkspace/xcshareddata/tuist/xcode-cache.xcconfig")

        #expect(XcodeBuildController.xcconfig(including: [user, packages]) == """
        #include "/tmp/my configs/Custom.xcconfig"
        #include "/repo/App.xcworkspace/xcshareddata/tuist/xcode-cache.xcconfig"

        """)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_whenWorkspaceHasNoXcodeCachePackagesXCConfig_doesNotSetXCConfigFile() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = temporaryDirectory.appending(component: "Project.xcworkspace")
        let arguments = ["build", "-workspace", xcworkspacePath.pathString, "-scheme", "App"]
        commandRunner.succeedCommand(["/usr/bin/xcrun", "xcodebuild"] + arguments)

        // When
        try await subject.run(arguments: arguments)

        // Then
        #expect(commandRunner.env["XCODE_XCCONFIG_FILE"] == nil)
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
