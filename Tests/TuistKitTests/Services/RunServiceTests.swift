import FileSystem
import Foundation
import MockableTest
import Path
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class RunServiceErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            RunServiceError.schemeNotFound(scheme: "Scheme", existing: ["A", "B"]).description,
            "Couldn't find scheme Scheme. The available schemes are: A, B."
        )
        XCTAssertEqual(
            RunServiceError.schemeWithoutRunnableTarget(scheme: "Scheme").description,
            "The scheme Scheme cannot be run because it contains no runnable target."
        )
        XCTAssertEqual(
            RunServiceError.invalidVersion("1.0.0").description,
            "The version 1.0.0 is not a valid version specifier."
        )
    }

    func test_type() {
        XCTAssertEqual(RunServiceError.schemeNotFound(scheme: "Scheme", existing: ["A", "B"]).type, .abort)
        XCTAssertEqual(RunServiceError.schemeWithoutRunnableTarget(scheme: "Scheme").type, .abort)
        XCTAssertEqual(RunServiceError.invalidVersion("1.0.0").type, .abort)
    }
}

final class RunServiceTests: TuistUnitTestCase {
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var targetBuilder: MockTargetBuilder!
    private var targetRunner: MockTargetRunner!
    private var configLoader: MockConfigLoading!
    private var downloadPreviewService: MockDownloadPreviewServicing!
    private var serverURLService: MockServerURLServicing!
    private var appRunner: MockAppRunning!
    private var subject: RunService!
    private var remoteArtifactDownloader: MockRemoteArtifactDownloading!
    private var appBundleLoader: MockAppBundleLoading!
    private var fileArchiverFactory: MockFileArchivingFactorying!

    private struct TestError: Equatable, Error {}

    override func setUp() {
        super.setUp()
        generator = .init()
        generatorFactory = MockGeneratorFactorying()
        given(generatorFactory)
            .defaultGenerator(config: .any)
            .willReturn(generator)
        buildGraphInspector = .init()
        targetBuilder = MockTargetBuilder()
        targetRunner = MockTargetRunner()
        configLoader = .init()
        downloadPreviewService = .init()
        appRunner = .init()
        remoteArtifactDownloader = .init()
        appBundleLoader = .init()
        fileArchiverFactory = .init()
        subject = RunService(
            generatorFactory: generatorFactory,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder,
            targetRunner: targetRunner,
            configLoader: configLoader,
            downloadPreviewService: downloadPreviewService,
            fileHandler: fileHandler,
            fileSystem: FileSystem(),
            appRunner: appRunner,
            remoteArtifactDownloader: remoteArtifactDownloader,
            appBundleLoader: appBundleLoader,
            fileArchiverFactory: fileArchiverFactory
        )
    }

    override func tearDown() {
        generator = nil
        buildGraphInspector = nil
        targetBuilder = nil
        targetRunner = nil
        subject = nil
        generatorFactory = nil
        super.tearDown()
    }

    func test_run_generates_when_generateIsTrue() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willReturn((try AbsolutePath(validating: "/path/to/project.xcworkspace"), .test(), MapperEnvironment()))
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(try! AbsolutePath(validating: "/path/to/project.xcworkspace"))
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test()])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        try await subject.run(generate: true)
    }

    func test_run_generates_when_workspaceNotFound() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        given(generator)
            .generateWithGraph(path: .any)
            .willReturn((workspacePath, .test(), MapperEnvironment()))
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test()])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.run()
    }

    func test_run_buildsTarget() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let schemeName = "AScheme"
        let clean = true
        let configuration = "Test"
        targetBuilder
            .buildTargetStub = { _, _workspacePath, _scheme, _clean, _configuration, _, _, _, _, _, _, _ in
                // Then
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertEqual(_scheme.name, schemeName)
                XCTAssertEqual(_clean, clean)
                XCTAssertEqual(_configuration, configuration)
            }
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        targetRunner.assertCanRunTargetStub = { _ in }
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test(name: schemeName)])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.run(
            runnable: .scheme(schemeName),
            clean: clean,
            configuration: configuration
        )
    }

    func test_run_runsTarget() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let schemeName = "AScheme"
        let configuration = "Test"
        let minVersion = Target.test().deploymentTargets.configuredVersions.first?.versionString.version()
        let version = Version("15.0.0")
        let deviceName = "iPhone 11"
        let arguments = ["-arg1", "--arg2", "SomeArgument"]
        targetRunner
            .runTargetStub = { _, _workspacePath, _schemeName, _configuration, _minVersion, _version, _deviceName, _arguments in
                // Then
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertEqual(_schemeName, schemeName)
                XCTAssertEqual(_configuration, configuration)
                XCTAssertEqual(_minVersion, minVersion)
                XCTAssertEqual(_version, version)
                XCTAssertEqual(_deviceName, deviceName)
                XCTAssertEqual(_arguments, arguments)
            }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        targetRunner.assertCanRunTargetStub = { _ in }
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test(name: schemeName)])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.run(
            runnable: .scheme(schemeName),
            configuration: configuration,
            device: deviceName,
            osVersion: version.description,
            arguments: arguments
        )
    }

    func test_run_throws_beforeBuilding_if_cantRunTarget() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let expectation = expectation(description: "does not run target builder")
        expectation.isInverted = true
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test()])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())
        targetBuilder.buildTargetStub = { _, _, _, _, _, _, _, _, _, _, _, _ in expectation.fulfill() }
        targetRunner.assertCanRunTargetStub = { _ in throw TestError() }

        // Then
        await XCTAssertThrowsSpecific(
            // When
            try await subject.run(),
            TestError()
        )
        await fulfillment(of: [expectation], timeout: 1)
    }

    func test_run_share_link_when_download_url_is_invalid() async throws {
        // Given
        given(downloadPreviewService)
            .downloadPreview(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example com/page")

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!)),
            RunServiceError.invalidDownloadBuildURL("https://example com/page")
        )
    }

    func test_run_share_link_when_app_build_artifact_not_found() async throws {
        // Given
        given(downloadPreviewService)
            .downloadPreview(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example.com")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(nil)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!)),
            RunServiceError.appNotFound("https://tuist.io/tuist/tuist/preview/some-id")
        )
    }

    func test_run_share_link_when_version_is_invalid() async throws {
        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!),
                osVersion: "invalid-version"
            ),
            RunServiceError.invalidVersion("invalid-version")
        )
    }

    func test_run_share_link_runs_app() async throws {
        // Given
        given(downloadPreviewService)
            .downloadPreview(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example.com")

        let downloadedArchive = try temporaryPath().appending(component: "archive")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        let unarchivedPath = try temporaryPath().appending(component: "unarchived")

        given(fileUnarchiver)
            .unzip()
            .willReturn(unarchivedPath)

        try fileHandler.touch(unarchivedPath.appending(component: "App.app"))

        given(appRunner)
            .runApp(
                .any,
                version: .any,
                device: .any
            )
            .willReturn()

        let appBundle: AppBundle = .test()
        given(appBundleLoader)
            .load(.any)
            .willReturn(appBundle)

        // When
        try await subject.run(runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!))

        // Then
        verify(appRunner)
            .runApp(
                .value([appBundle]),
                version: .value(nil),
                device: .value(nil)
            )
            .called(1)
    }

    func test_run_share_link_runs_with_destination_and_version() async throws {
        // Given
        given(downloadPreviewService)
            .downloadPreview(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example.com")

        let downloadedArchive = try temporaryPath().appending(component: "archive")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        let unarchivedPath = try temporaryPath().appending(component: "unarchived")

        given(fileUnarchiver)
            .unzip()
            .willReturn(unarchivedPath)

        try fileHandler.touch(unarchivedPath.appending(component: "App.app"))

        given(appRunner)
            .runApp(
                .any,
                version: .any,
                device: .any
            )
            .willReturn()

        let appBundle: AppBundle = .test()
        given(appBundleLoader)
            .load(.any)
            .willReturn(appBundle)

        // When
        try await subject.run(
            runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!),
            osVersion: "18.0",
            arguments: ["-destination", "iPhone 15 Pro"]
        )

        // Then
        verify(appRunner)
            .runApp(
                .value([appBundle]),
                version: .value("18.0.0"),
                device: .value("iPhone 15 Pro")
            )
            .called(1)
    }
}

extension RunService {
    fileprivate func run(
        runnable: Runnable = .scheme(Scheme.test().name),
        generate: Bool = false,
        clean: Bool = false,
        configuration: String? = nil,
        device: String? = nil,
        osVersion: String? = nil,
        rosetta: Bool = false,
        arguments: [String] = []
    ) async throws {
        try await run(
            path: nil,
            runnable: runnable,
            generate: generate,
            clean: clean,
            configuration: configuration,
            device: device,
            osVersion: osVersion,
            rosetta: rosetta,
            arguments: arguments
        )
    }
}
