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
    private var subject: TargetBuilder!

    override func setUp() {
        super.setUp()
        buildGraphInspector = MockBuildGraphInspector()
        xcodeBuildController = MockXcodeBuildController()
        xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocator()
        subject = TargetBuilder(
            buildGraphInspector: buildGraphInspector,
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator
        )
    }

    override func tearDown() {
        buildGraphInspector = nil
        xcodeBuildController = nil
        xcodeProjectBuildDirectoryLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_buildScheme_callsXcodeBuildControllerWithArguments() async throws {
        // Given
        let scheme = Scheme.test(name: "A")
        let workspacePath = AbsolutePath("/path/to/project.xcworkspace")
        let configuration = "TestRelease"
        let clean = false
        let buildArguments: [XcodeBuildArgument] = [
            .configuration(configuration),
            .sdk("iphoneos"),
        ]

        buildGraphInspector.buildArgumentsStub = { _, _, _, _ in
            buildArguments
        }

        xcodeBuildController.buildStub = { _workspace, _scheme, _clean, _buildArguments in
            XCTAssertEqual(_workspace.path, workspacePath)
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertEqual(_clean, clean)
            XCTAssertEqual(_buildArguments, buildArguments)
            return [.standardOutput(.init(raw: "success"))]
        }

        // When
        try await subject.buildTarget(
            .test(),
            workspacePath: workspacePath,
            schemeName: scheme.name,
            clean: clean,
            configuration: configuration,
            buildOutputPath: nil
        )
    }

    func test_copiesBuildProducts_to_outputPath_defaultConfiguration() async throws {
        // Given
        let path = try temporaryPath()
        let buildOutputPath = path.appending(component: ".build")
        let scheme = Scheme.test(name: "A")
        let workspacePath = AbsolutePath("/path/to/project.xcworkspace")

        xcodeBuildController.buildStub = { _, _, _, _ in
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
            schemeName: scheme.name,
            clean: false,
            configuration: nil,
            buildOutputPath: buildOutputPath
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
        let workspacePath = AbsolutePath("/path/to/project.xcworkspace")

        xcodeBuildController.buildStub = { _, _, _, _ in
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
            schemeName: scheme.name,
            clean: false,
            configuration: configuration,
            buildOutputPath: buildOutputPath
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
