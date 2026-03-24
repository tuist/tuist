import FileSystem
import FileSystemTesting
import Mockable
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistOpener
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistAutomation

struct TargetRunnerErrorTests {
    @Test
    func description() {
        #expect(TargetRunnerError.runnableNotFound(path: "/path/to/product")
            .localizedDescription == "The runnable product was expected but not found at /path/to/product.")
        #expect(TargetRunnerError.runningNotSupported(target: .test(platform: .iOS, product: .app))
            .localizedDescription == "Product type app of Target is not runnable")
    }
}

struct TargetRunnerTests {
    private let system = MockSystem()
    private let fileSystem = FileSystem()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocating()
    private let simulatorController = MockSimulatorControlling()
    private let opener = MockOpening()
    private let subject: TargetRunner
    init() {
        subject = TargetRunner(
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            simulatorController: simulatorController,
            opener: opener
        )
    }

    @Test(.inTemporaryDirectory)
    func throwsError_when_buildProductNotFound() async throws {
        // Given
        let target = GraphTarget.test()
        let path = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = path.appending(component: "App.xcworkspace")
        let outputPath = path.appending(component: ".build")
        let productPath = outputPath.appending(component: "Target.app")
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(outputPath)

        // When / Then
        await #expect(throws: TargetRunnerError.runnableNotFound(path: productPath.pathString)) { try await subject.runTarget(
            target,
            platform: .iOS,
            workspacePath: workspacePath,
            schemeName: "MyScheme",
            configuration: nil,
            minVersion: nil,
            version: nil,
            deviceName: nil,
            arguments: []
        ) }
    }

    @Test(.inTemporaryDirectory)
    func usesDefaultConfiguration_when_noConfiguration() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = path.appending(component: "App.xcworkspace")
        try await fileSystem.makeDirectory(at: workspacePath)
        try await fileSystem.touch(workspacePath.appending(component: "Target"))
        system.succeedCommand(
            [
                workspacePath.appending(component: "Target").pathString,
            ]
        )

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(workspacePath)

        // When
        try await subject.runTarget(
            .test(target: .test(platform: .macOS, product: .commandLineTool)),
            platform: .macOS,
            workspacePath: workspacePath,
            schemeName: "MyScheme",
            configuration: nil,
            minVersion: nil,
            version: nil,
            deviceName: nil,
            arguments: []
        )

        // Then
        verify(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .value(BuildConfiguration.debug.name)
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory)
    func runsExecutable_when_platform_is_macOS_and_product_is_commandLineTool() async throws {
        // Given
        let workspacePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "App.xcworkspace")
        let target = Target.test(platform: .macOS, product: .commandLineTool)
        let graphTarget = GraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try #require(FileSystem.temporaryTestDirectory).appending(component: ".build")
        let executablePath = outputPath.appending(component: target.productNameWithExtension)
        let arguments = ["Argument", "--option1", "AnotherArgument", "--option2=true", "-opt3"]

        try await fileSystem.makeDirectory(at: outputPath)
        try await fileSystem.touch(outputPath.appending(component: "Target"))
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(outputPath)
        system.succeedCommand([executablePath.pathString] + arguments)

        // THEN
        do {
            try await subject.runTarget(
                graphTarget,
                platform: .macOS,
                workspacePath: workspacePath,
                schemeName: "MyScheme",
                configuration: nil,
                minVersion: nil,
                version: nil,
                deviceName: nil,
                arguments: arguments
            )
        } catch {
            Issue.record("Should not throw")
        }
    }

    @Test(.inTemporaryDirectory)
    func runsApp_when_platform_is_iOS_and_product_is_app() async throws {
        // Given
        let workspacePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "App.xcworkspace")
        let target = Target.test(platform: .iOS, product: .app)
        let graphTarget = GraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try #require(FileSystem.temporaryTestDirectory).appending(component: ".build")
        let appPath = outputPath.appending(component: target.productNameWithExtension)
        let arguments = ["Argument", "--option1", "AnotherArgument", "--option2=true", "-opt3"]
        let minVersion = Version("14.0.0")
        let version = Version("15.0.0")
        let deviceName = "iPhone 11"
        let bundleId = "dev.tuist.bundleid"

        try await fileSystem.makeDirectory(at: outputPath)
        try await fileSystem.touch(outputPath.appending(component: "Target.app"))
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(outputPath)
        given(xcodeBuildController)
            .showBuildSettings(
                .any,
                scheme: .any,
                configuration: .any,
                derivedDataPath: .any
            )
            .willReturn(
                [
                    graphTarget.target
                        .name: XcodeBuildSettings(
                            ["PRODUCT_BUNDLE_IDENTIFIER": bundleId],
                            target: graphTarget.target.name, configuration: "Debug"
                        ),
                ]
            )
        given(simulatorController)
            .launchApp(
                bundleId: .any,
                device: .any,
                arguments: .any
            )
            .willReturn()
        given(simulatorController)
            .askForAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(.test())

        given(simulatorController)
            .installApp(
                at: .any,
                device: .any
            )
            .willReturn()

        // Then
        try await subject.runTarget(
            graphTarget,
            platform: .iOS,
            workspacePath: workspacePath,
            schemeName: "MyScheme",
            configuration: nil,
            minVersion: minVersion,
            version: version,
            deviceName: deviceName,
            arguments: arguments
        )

        verify(simulatorController)
            .askForAvailableDevice(
                platform: .value(.iOS),
                version: .value(version),
                minVersion: .value(minVersion),
                deviceName: .value(deviceName)
            )
            .called(1)

        verify(simulatorController)
            .installApp(
                at: .value(appPath),
                device: .any
            )
            .called(1)

        verify(simulatorController)
            .launchApp(
                bundleId: .value(bundleId),
                device: .any,
                arguments: .value(arguments)
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory)
    func runsApp_when_platform_is_macOS_and_product_is_app_and_device_is_absent() async throws {
        // Given
        let workspacePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "App.xcworkspace")
        let target = Target.test(destinations: [.mac], product: .app)
        let graphTarget = GraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try #require(FileSystem.temporaryTestDirectory).appending(component: ".build")
        let appPath = outputPath.appending(component: target.productNameWithExtension)
        let arguments: [String] = []
        let minVersion = Version("14.0.0")
        let version = Version("15.0.0")
        let deviceName: String? = nil
        let bundleId = "dev.tuist.bundleid"

        try await fileSystem.makeDirectory(at: outputPath)
        try await fileSystem.touch(outputPath.appending(component: "Target.app"))
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(outputPath)
        given(xcodeBuildController)
            .showBuildSettings(
                .any,
                scheme: .any,
                configuration: .any,
                derivedDataPath: .any
            )
            .willReturn(
                [
                    graphTarget.target
                        .name: XcodeBuildSettings(
                            ["PRODUCT_BUNDLE_IDENTIFIER": bundleId],
                            target: graphTarget.target.name, configuration: "Debug"
                        ),
                ]
            )
        given(opener).open(path: .value(appPath)).willReturn()

        // Then
        try await subject.runTarget(
            graphTarget,
            platform: .iOS,
            workspacePath: workspacePath,
            schemeName: "MyScheme",
            configuration: nil,
            minVersion: minVersion,
            version: version,
            deviceName: deviceName,
            arguments: arguments
        )

        verify(opener).open(path: .value(appPath)).called(1)
    }

    @Test(.inTemporaryDirectory)
    func runsApp_when_platform_is_macOS_and_product_is_app_and_device_is_macos() async throws {
        // Given
        let workspacePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "App.xcworkspace")
        let target = Target.test(destinations: [.mac], product: .app)
        let graphTarget = GraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try #require(FileSystem.temporaryTestDirectory).appending(component: ".build")
        let appPath = outputPath.appending(component: target.productNameWithExtension)
        let arguments: [String] = []
        let minVersion = Version("14.0.0")
        let version = Version("15.0.0")
        let deviceName = "macOS"
        let bundleId = "dev.tuist.bundleid"

        try await fileSystem.makeDirectory(at: outputPath)
        try await fileSystem.touch(outputPath.appending(component: "Target.app"))
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(outputPath)
        given(xcodeBuildController)
            .showBuildSettings(
                .any,
                scheme: .any,
                configuration: .any,
                derivedDataPath: .any
            )
            .willReturn(
                [
                    graphTarget.target
                        .name: XcodeBuildSettings(
                            ["PRODUCT_BUNDLE_IDENTIFIER": bundleId],
                            target: graphTarget.target.name, configuration: "Debug"
                        ),
                ]
            )
        given(opener).open(path: .value(appPath)).willReturn()

        // Then
        try await subject.runTarget(
            graphTarget,
            platform: .iOS,
            workspacePath: workspacePath,
            schemeName: "MyScheme",
            configuration: nil,
            minVersion: minVersion,
            version: version,
            deviceName: deviceName,
            arguments: arguments
        )

        verify(opener).open(path: .value(appPath)).called(1)
    }
}
