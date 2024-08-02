import MockableTest
import Path
import TuistAutomationTesting
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting

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
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var xcodeBuildController: MockXcodeBuildControlling!
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocating!
    private var simulatorController: MockSimulatorControlling!
    private var subject: TargetBuilder!

    override func setUp() {
        super.setUp()
        buildGraphInspector = .init()
        xcodeBuildController = .init()
        xcodeProjectBuildDirectoryLocator = .init()
        simulatorController = .init()
        subject = TargetBuilder(
            buildGraphInspector: buildGraphInspector,
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            simulatorController: simulatorController
        )

        given(xcodeBuildController)
            .build(
                .any,
                scheme: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                clean: .any,
                arguments: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willReturn()
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
        let version = Version("15.2")
        let rosetta = true
        let device = "iPhone 13 Pro"

        given(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(
                .test(device: SimulatorDevice.test(udid: "this_is_a_udid"))
            )
        given(buildGraphInspector)
            .buildArguments(
                project: .any,
                target: .any,
                configuration: .any,
                skipSigning: .any
            )
            .willReturn(buildArguments)

        // When
        try await subject.buildTarget(
            .test(),
            platform: .iOS,
            workspacePath: workspacePath,
            scheme: scheme,
            clean: clean,
            configuration: configuration,
            buildOutputPath: nil,
            derivedDataPath: nil,
            device: device,
            osVersion: version,
            rosetta: rosetta,
            graphTraverser: MockGraphTraversing(),
            passthroughXcodeBuildArguments: []
        )

        // Then
        verify(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .value("15.2".version()),
                minVersion: .any,
                deviceName: .value(device)
            )
            .called(1)

        verify(xcodeBuildController)
            .build(
                .any,
                scheme: .value(scheme.name),
                destination: .value(destination),
                rosetta: .value(rosetta),
                derivedDataPath: .value(nil),
                clean: .value(clean),
                arguments: .value(buildArguments),
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_copiesBuildProducts_to_outputPath_defaultConfiguration() async throws {
        // Given
        let path = try temporaryPath()
        let buildOutputPath = path.appending(component: ".build")
        let scheme = Scheme.test(name: "A")
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let graphTraverser = MockGraphTraversing()

        let xcodeBuildPath = path.appending(components: "Xcode", "DerivedData", "MyProject-hash", "Debug")
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(xcodeBuildPath)
        try createFiles([
            "Xcode/DerivedData/MyProject-hash/Debug/App.app",
            "Xcode/DerivedData/MyProject-hash/Debug/App.swiftmodule",
        ])

        given(buildGraphInspector)
            .buildArguments(
                project: .any,
                target: .any,
                configuration: .any,
                skipSigning: .any
            )
            .willReturn([])

        given(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(.test())

        // When
        try await subject.buildTarget(
            .test(),
            platform: .iOS,
            workspacePath: workspacePath,
            scheme: scheme,
            clean: false,
            configuration: nil,
            buildOutputPath: buildOutputPath,
            derivedDataPath: nil,
            device: nil,
            osVersion: nil,
            rosetta: false,
            graphTraverser: graphTraverser,
            passthroughXcodeBuildArguments: []
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
        let graphTraverser = MockGraphTraversing()

        given(buildGraphInspector)
            .buildArguments(
                project: .any,
                target: .any,
                configuration: .any,
                skipSigning: .any
            )
            .willReturn([])

        given(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(.test())

        let xcodeBuildPath = path.appending(components: "Xcode", "DerivedData", "MyProject-hash", configuration)
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .any,
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(xcodeBuildPath)
        try createFiles([
            "Xcode/DerivedData/MyProject-hash/\(configuration)/App.app",
            "Xcode/DerivedData/MyProject-hash/\(configuration)/App.swiftmodule",
        ])

        // When
        try await subject.buildTarget(
            .test(),
            platform: .iOS,
            workspacePath: workspacePath,
            scheme: scheme,
            clean: false,
            configuration: configuration,
            buildOutputPath: buildOutputPath,
            derivedDataPath: nil,
            device: nil,
            osVersion: nil,
            rosetta: false,
            graphTraverser: graphTraverser,
            passthroughXcodeBuildArguments: []
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
