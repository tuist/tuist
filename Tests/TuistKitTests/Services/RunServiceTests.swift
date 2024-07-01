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
    private var downloadAppBuildService: MockDownloadAppBuildServicing!
    private var serverURLService: MockServerURLServicing!
    private var appRunner: MockAppRunning!
    private var subject: RunService!
    private var remoteArtifactDownloader: MockRemoteArtifactDownloading!
    private var appBundleService: MockAppBundleServicing!
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
        downloadAppBuildService = .init()
        serverURLService = .init()
        appRunner = .init()
        remoteArtifactDownloader = .init()
        appBundleService = .init()
        fileArchiverFactory = .init()
        subject = RunService(
            generatorFactory: generatorFactory,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder,
            targetRunner: targetRunner,
            configLoader: configLoader,
            downloadAppBuildService: downloadAppBuildService,
            serverURLService: serverURLService,
            fileHandler: fileHandler,
            appRunner: appRunner,
            remoteArtifactDownloader: remoteArtifactDownloader,
            appBundleService: appBundleService,
            fileArchiverFactory: fileArchiverFactory
        )

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)
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
            .willReturn((try AbsolutePath(validating: "/path/to/project.xcworkspace"), .test()))
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
            .willReturn((workspacePath, .test()))
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
            schemeOrShareLink: schemeName,
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
            schemeOrShareLink: schemeName,
            configuration: configuration,
            device: deviceName,
            version: version.description,
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

    func test_run_share_link_when_full_handle_is_undefined() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(schemeOrShareLink: "https://tuist.io/share/some-id"),
            RunServiceError.fullHandleNotFound
        )
    }

    func test_run_share_link_when_download_url_is_invalid() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(downloadAppBuildService)
            .downloadAppBuild(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example com/page")

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(schemeOrShareLink: "https://tuist.io/share/some-id"),
            RunServiceError.invalidDownloadBuildURL("https://example com/page")
        )
    }

    func test_run_share_link_when_app_build_artifact_not_found() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(downloadAppBuildService)
            .downloadAppBuild(
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
            try await subject.run(schemeOrShareLink: "https://tuist.io/share/some-id"),
            RunServiceError.appNotFound("https://tuist.io/share/some-id")
        )
    }

    func test_run_share_link_when_version_is_invalid() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                schemeOrShareLink: "https://tuist.io/share/some-id",
                version: "invalid-version"
            ),
            RunServiceError.invalidVersion("invalid-version")
        )
    }

    func test_run_share_link_runs_app() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(downloadAppBuildService)
            .downloadAppBuild(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example.com")

        let downloadedArchive = try temporaryPath()

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        let unarchivedPath = try temporaryPath()

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
        given(appBundleService)
            .read(.any)
            .willReturn(appBundle)

        // When
        try await subject.run(schemeOrShareLink: "https://tuist.io/share/some-id")

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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(downloadAppBuildService)
            .downloadAppBuild(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn("https://example.com")

        let downloadedArchive = try temporaryPath()

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        let unarchivedPath = try temporaryPath()

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
        given(appBundleService)
            .read(.any)
            .willReturn(appBundle)

        // When
        try await subject.run(
            schemeOrShareLink: "https://tuist.io/share/some-id",
            version: "18.0",
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
        schemeOrShareLink: String = Scheme.test().name,
        generate: Bool = false,
        clean: Bool = false,
        configuration: String? = nil,
        device: String? = nil,
        version: String? = nil,
        rosetta: Bool = false,
        arguments: [String] = []
    ) async throws {
        try await run(
            path: nil,
            schemeOrShareLink: schemeOrShareLink,
            generate: generate,
            clean: clean,
            configuration: configuration,
            device: device,
            version: version,
            rosetta: rosetta,
            arguments: arguments
        )
    }
}
