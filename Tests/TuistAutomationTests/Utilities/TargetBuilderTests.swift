import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class TargetBuilderErrorTests: XCTestCase {
    func test_errorDescription() {
        XCTAssertEqual(
            TargetBuilderError.schemeWithoutBuildableTargets(scheme: "MyScheme").description,
            "The scheme MyScheme cannot be built because it contains no buildable targets."
        )
        XCTAssertEqual(
            TargetBuilderError.buildProductsNotFound(path: "/path/to/products").description,
            "The expected build products at /path/to/products were not found."
        )
    }

    func test_errorType() {
        XCTAssertEqual(TargetBuilderError.schemeWithoutBuildableTargets(scheme: "MyScheme").type, .abort)
        XCTAssertEqual(TargetBuilderError.buildProductsNotFound(path: "/path/to/products").type, .bug)
    }
}

final class TargetBuilderTests: TuistUnitTestCase {
    private var buildGraphInspector: MockBuildGraphInspector!
    private var xcodeBuildController: MockXcodeBuildController!
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocator!
    private var simulatorController: MockSimulatorController!
    private var subject: TargetBuilder!

    override func setUp() {
        super.setUp()
        buildGraphInspector = MockBuildGraphInspector()
        xcodeBuildController = MockXcodeBuildController()
        xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocator()
        simulatorController = MockSimulatorController()
        subject = TargetBuilder(
            buildGraphInspector: buildGraphInspector,
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            simulatorController: simulatorController
        )
    }

    override func tearDown() {
        buildGraphInspector = nil
        xcodeBuildController = nil
        xcodeProjectBuildDirectoryLocator = nil
        simulatorController = nil
        subject = nil
        super.tearDown()
    }

    func test_buildScheme_callsXcodeBuildControllerWithArguments() async throws {
        // Given
        let scheme = Scheme.test(name: "A")
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let configuration = "TestRelease"
        let clean = false
        let buildArguments: [XcodeBuildArgument] = [
            .configuration(configuration),
            .sdk("iphoneos"),
        ]
        let destination = XcodeBuildDestination.device("this_is_a_udid")
        let version = "15.2".version()
        let device = "iPhone 13 Pro"

        simulatorController.findAvailableDeviceStub = { _, _version, _, _deviceName in
            XCTAssertEqual(_version, version)
            XCTAssertEqual(_deviceName, device)

            return .test(device: SimulatorDevice.test(udid: "this_is_a_udid"))
        }
        buildGraphInspector.buildArgumentsStub = { _, _, _, _ in
            buildArguments
        }

        xcodeBuildController.buildStub = { _workspace, _scheme, _destination, _clean, _buildArguments in
            XCTAssertEqual(_workspace.path, workspacePath)
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertEqual(_destination, destination)
            XCTAssertEqual(_clean, clean)
            XCTAssertEqual(_buildArguments, buildArguments)
            return [.standardOutput(.init(raw: "success"))]
        }

        // When
        try await subject.buildTarget(
            .test(),
            workspacePath: workspacePath,
            scheme: scheme,
            clean: clean,
            configuration: configuration,
            buildOutputPath: nil,
            device: device,
            osVersion: version,
            graphTraverser: MockGraphTraverser()
        )
    }

    func test_copiesBuildProducts_to_outputPath_defaultConfiguration() async throws {
        // Given
        let path = try temporaryPath()
        let buildOutputPath = path.appending(component: ".build")
        let scheme = Scheme.test(name: "A")
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let graphTraverser = MockGraphTraverser()

        xcodeBuildController.buildStub = { _, _, _, _, _ in
            [.standardOutput(.init(raw: "success"))]
        }

        let xcodeBuildPath = path.appending(components: "Xcode", "DerivedData", "MyProject-hash", "Debug")
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _ in xcodeBuildPath }
        try createFiles([
            "Xcode/DerivedData/MyProject-hash/Debug/App.app",
            "Xcode/DerivedData/MyProject-hash/Debug/App.swiftmodule",
        ])

        // When
        try await subject.buildTarget(
            .test(),
            workspacePath: workspacePath,
            scheme: scheme,
            clean: false,
            configuration: nil,
            buildOutputPath: buildOutputPath,
            device: nil,
            osVersion: nil,
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(buildOutputPath).sorted(),
            [buildOutputPath.appending(component: "Debug")]
        )

        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(buildOutputPath.appending(component: "Debug")).sorted(),
            [
                buildOutputPath.appending(components: "Debug", "App.app"),
                buildOutputPath.appending(components: "Debug", "App.swiftmodule"),
            ]
        )
    }

    func test_copiesBuildProducts_to_outputPath_customConfiguration() async throws {
        // Given
        let path = try temporaryPath()
        let buildOutputPath = path.appending(component: ".build")
        let scheme = Scheme.test(name: "A")
        let configuration = "TestRelease"
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let graphTraverser = MockGraphTraverser()

        xcodeBuildController.buildStub = { _, _, _, _, _ in
            [.standardOutput(.init(raw: "success"))]
        }

        let xcodeBuildPath = path.appending(components: "Xcode", "DerivedData", "MyProject-hash", configuration)
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _ in xcodeBuildPath }
        try createFiles([
            "Xcode/DerivedData/MyProject-hash/\(configuration)/App.app",
            "Xcode/DerivedData/MyProject-hash/\(configuration)/App.swiftmodule",
        ])

        // When
        try await subject.buildTarget(
            .test(),
            workspacePath: workspacePath,
            scheme: scheme,
            clean: false,
            configuration: configuration,
            buildOutputPath: buildOutputPath,
            device: nil,
            osVersion: nil,
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(buildOutputPath).sorted(),
            [buildOutputPath.appending(component: configuration)]
        )

        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(buildOutputPath.appending(component: configuration)).sorted(),
            [
                buildOutputPath.appending(components: configuration, "App.app"),
                buildOutputPath.appending(components: configuration, "App.swiftmodule"),
            ]
        )
    }
}
