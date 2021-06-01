import RxSwift
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class TargetRunnerErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(
            TargetRunnerError.runnableNotFound(path: "/path/to/product").description,
            "The runnable product was expected but not found at /path/to/product."
        )
        XCTAssertEqual(
            TargetRunnerError.runningNotSupported(target: .test(platform: .iOS, product: .app)).description,
            "Cannot run Target - the platform iOS and product type app are not currently supported."
        )
    }

    func test_type() {
        XCTAssertEqual(TargetRunnerError.runnableNotFound(path: "/path").type, .bug)
        XCTAssertEqual(TargetRunnerError.runningNotSupported(target: .test(platform: .iOS, product: .app)).type, .abort)
    }
}

final class TargetRunnerTests: TuistUnitTestCase {
    private var xcodeBuildController: MockXcodeBuildController!
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocator!
    private var simulatorController: MockSimulatorController!
    private var subject: TargetRunner!

    override func setUp() {
        xcodeBuildController = MockXcodeBuildController()
        xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocator()
        simulatorController = MockSimulatorController()
        subject = TargetRunner(
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            simulatorController: simulatorController
        )
        super.setUp()
    }

    override func tearDown() {
        xcodeBuildController = nil
        xcodeProjectBuildDirectoryLocator = nil
        simulatorController = nil
        subject = nil
        super.tearDown()
    }

    func test_throwsError_when_buildProductNotFound() throws {
        // Given
        let target = ValueGraphTarget.test()
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let outputPath = path.appending(component: ".build")
        let productPath = outputPath.appending(component: "Target.app")
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _ in outputPath }
        fileHandler.stubExists = { _ in false }

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.runTarget(
                target,
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

    func test_usesDefaultConfiguration_when_noConfiguration() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        fileHandler.stubExists = { _ in true }
        system.succeedCommand("/path/to/proj.xcworkspace/Target")

        let expectation = self.expectation(description: "locates with default configuration")
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _configuration in
            // THEN
            XCTAssertEqual(_configuration, BuildConfiguration.debug.name)
            expectation.fulfill()
            return AbsolutePath("/path/to/proj.xcworkspace")
        }

        // WHEN
        try subject.runTarget(
            .test(target: .test(platform: .macOS, product: .commandLineTool)),
            workspacePath: workspacePath,
            schemeName: "MyScheme",
            configuration: nil,
            minVersion: nil,
            version: nil,
            deviceName: nil,
            arguments: []
        )

        waitForExpectations(timeout: 1.0)
    }

    func test_runsExecutable_when_platform_is_macOS_and_product_is_commandLineTool() throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let target = Target.test(platform: .macOS, product: .commandLineTool)
        let graphTarget = ValueGraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try temporaryPath().appending(component: ".build")
        let executablePath = outputPath.appending(component: target.productNameWithExtension)
        let arguments = ["Argument", "--option1", "AnotherArgument", "--option2=true", "-opt3"]

        fileHandler.stubExists = { _ in true }
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _ in outputPath }
        system.succeedCommand([executablePath.pathString] + arguments)

        // THEN
        XCTAssertNoThrow(
            // WHEN
            try subject.runTarget(
                graphTarget,
                workspacePath: workspacePath,
                schemeName: "MyScheme",
                configuration: nil,
                minVersion: nil,
                version: nil,
                deviceName: nil,
                arguments: arguments
            )
        )
    }

    func test_runsApp_when_platform_is_iOS_and_product_is_app() throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let target = Target.test(platform: .iOS, product: .app)
        let graphTarget = ValueGraphTarget.test(path: workspacePath, target: target, project: .test())
        let outputPath = try temporaryPath().appending(component: ".build")
        let appPath = outputPath.appending(component: target.productNameWithExtension)
        let arguments = ["Argument", "--option1", "AnotherArgument", "--option2=true", "-opt3"]
        let minVersion = Version(string: "14.0")
        let version = Version(string: "15.0")
        let deviceName = "iPhone 11"
        let bundleId = "com.tuist.bundleid"

        fileHandler.stubExists = { _ in true }
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _ in outputPath }
        xcodeBuildController.showBuildSettingsStub = { _, _, _ in
            let settings = ["PRODUCT_BUNDLE_IDENTIFIER": bundleId]
            return .just([graphTarget.target.name: XcodeBuildSettings(settings, target: graphTarget.target.name, configuration: "Debug")])
        }
        simulatorController.findAvailableDeviceStub = { _platform, _version, _minVersion, _deviceName in
            XCTAssertEqual(_platform, .iOS)
            XCTAssertEqual(_version, version)
            XCTAssertEqual(_minVersion, minVersion)
            XCTAssertEqual(_deviceName, deviceName)
            return .just(.test(device: .test(), runtime: .test()))
        }
        simulatorController.installAppStub = { _appPath, _ in
            XCTAssertEqual(_appPath, appPath)
        }
        simulatorController.launchAppStub = { _bundleId, _, _arguments in
            XCTAssertEqual(_bundleId, bundleId)
            XCTAssertEqual(_arguments, arguments)
        }

        // THEN
        XCTAssertNoThrow(
            // WHEN
            try subject.runTarget(
                graphTarget,
                workspacePath: workspacePath,
                schemeName: "MyScheme",
                configuration: nil,
                minVersion: minVersion,
                version: version,
                deviceName: deviceName,
                arguments: arguments
            )
        )
    }
}
