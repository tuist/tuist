import MockableTest
import Path
import struct TSCUtility.Version
import TuistAutomationTesting
import TuistCore
import TuistCoreTesting
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistAutomation

final class TargetRunnerErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(
            TargetRunnerError.runnableNotFound(path: "/path/to/product").description,
            "The runnable product was expected but not found at /path/to/product."
        )
        XCTAssertEqual(
            TargetRunnerError.runningNotSupported(target: .test(platform: .iOS, product: .app)).description,
            "Product type app of Target is not runnable"
        )
    }

    func test_type() {
        XCTAssertEqual(TargetRunnerError.runnableNotFound(path: "/path").type, .bug)
        XCTAssertEqual(TargetRunnerError.runningNotSupported(target: .test(platform: .iOS, product: .app)).type, .abort)
    }
}

final class TargetRunnerTests: TuistUnitTestCase {
    private var xcodeBuildController: MockXcodeBuildControlling!
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocating!
    private var simulatorController: MockSimulatorControlling!
    private var subject: TargetRunner!

    override func setUp() {
        super.setUp()
        xcodeBuildController = .init()
        xcodeProjectBuildDirectoryLocator = .init()
        simulatorController = .init()
        subject = TargetRunner(
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            simulatorController: simulatorController
        )
    }

    override func tearDown() {
        xcodeBuildController = nil
        xcodeProjectBuildDirectoryLocator = nil
        simulatorController = nil
        subject = nil
        super.tearDown()
    }

    func test_throwsError_when_buildProductNotFound() async throws {
        // Given
        let target = GraphTarget.test()
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let outputPath = path.appending(component: ".build")
        let productPath = outputPath.appending(component: "Target.app")
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(outputPath)
        fileHandler.stubExists = { _ in false }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.runTarget(
                target,
                platform: .iOS,
                workspacePath: workspacePath,
                schemeName: "MyScheme",
                configuration: nil,
                minVersion: nil,
                version: nil,
                deviceName: nil,
                arguments: []
            ),
            TargetRunnerError.runnableNotFound(path: productPath.pathString)
        )
    }

    func test_usesDefaultConfiguration_when_noConfiguration() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        fileHandler.stubExists = { _ in true }
        system.succeedCommand(["/path/to/proj.xcworkspace/Target"])

        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(try AbsolutePath(validating: "/path/to/proj.xcworkspace"))

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
                platform: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .value(BuildConfiguration.debug.name)
            )
            .called(1)
    }

    func test_runsExecutable_when_platform_is_macOS_and_product_is_commandLineTool() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let target = Target.test(platform: .macOS, product: .commandLineTool)
        let graphTarget = GraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try temporaryPath().appending(component: ".build")
        let executablePath = outputPath.appending(component: target.productNameWithExtension)
        let arguments = ["Argument", "--option1", "AnotherArgument", "--option2=true", "-opt3"]

        fileHandler.stubExists = { _ in true }
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .any,
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
            XCTFail("Should not throw")
        }
    }

    func test_runsApp_when_platform_is_iOS_and_product_is_app() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let target = Target.test(platform: .iOS, product: .app)
        let graphTarget = GraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try temporaryPath().appending(component: ".build")
        let appPath = outputPath.appending(component: target.productNameWithExtension)
        let arguments = ["Argument", "--option1", "AnotherArgument", "--option2=true", "-opt3"]
        let minVersion = Version("14.0.0")
        let version = Version("15.0.0")
        let deviceName = "iPhone 11"
        let bundleId = "com.tuist.bundleid"

        fileHandler.stubExists = { _ in true }
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .any,
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
}
