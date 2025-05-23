import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

import struct TSCUtility.Version

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

struct RunCommandServiceErrorTests {
    @Test
    func test_description() {
        #expect(
            RunCommandServiceError.schemeNotFound(scheme: "Scheme", existing: ["A", "B"])
                .errorDescription == "Couldn't find scheme Scheme. The available schemes are: A, B."
        )
        #expect(
            RunCommandServiceError.schemeWithoutRunnableTarget(scheme: "Scheme").errorDescription
                == "The scheme Scheme cannot be run because it contains no runnable target."
        )
        #expect(
            RunCommandServiceError.invalidVersion("1.0.0").errorDescription
                == "The version 1.0.0 is not a valid version specifier."
        )
    }
}

struct RunCommandServiceTests {
    private let generator = MockGenerating()
    private let generatorFactory = MockGeneratorFactorying()
    private let buildGraphInspector = MockBuildGraphInspecting()
    private let targetBuilder = MockTargetBuilder()
    private let targetRunner = MockTargetRunner()
    private let configLoader = MockConfigLoading()
    private let getPreviewService = MockGetPreviewServicing()
    private let listPreviewsService = MockListPreviewsServicing()
    private let serverURLService = MockServerURLServicing()
    private let appRunner = MockAppRunning()
    private let remoteArtifactDownloader = MockRemoteArtifactDownloading()
    private let appBundleLoader = MockAppBundleLoading()
    private let fileArchiverFactory = MockFileArchivingFactorying()
    private let fileSystem = FileSystem()
    private let subject: RunCommandService

    private struct TestError: Equatable, Error {}
    init() {
        given(generatorFactory)
            .defaultGenerator(config: .any, includedTargets: .any)
            .willReturn(generator)
        subject = RunCommandService(
            generatorFactory: generatorFactory,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder,
            targetRunner: targetRunner,
            configLoader: configLoader,
            getPreviewService: getPreviewService,
            listPreviewsService: listPreviewsService,
            fileSystem: FileSystem(),
            appRunner: appRunner,
            remoteArtifactDownloader: remoteArtifactDownloader,
            appBundleLoader: appBundleLoader,
            fileArchiverFactory: fileArchiverFactory
        )
    }

    @Test
    func test_run_generates_when_generateIsTrue() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willReturn(
                (
                    try AbsolutePath(validating: "/path/to/project.xcworkspace"), .test(),
                    MapperEnvironment()
                )
            )
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

    @Test
    func test_run_generates_when_workspaceNotFound() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
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
    }

    @Test
    func test_run_buildsTarget() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            let schemeName = "AScheme"
            let clean = true
            let configuration = "Test"
            targetBuilder
                .buildTargetStub = {
                    _, _workspacePath, _scheme, _clean, _configuration, _, _, _, _, _, _, _ in
                    // Then
                    #expect(_workspacePath == workspacePath)
                    #expect(_scheme.name == schemeName)
                    #expect(_clean == clean)
                    #expect(_configuration == configuration)
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
    }

    @Test
    func test_run_runsTarget() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let schemeName = "AScheme"
        let configuration = "Test"
        let minVersion = Target.test().deploymentTargets.configuredVersions.first?.versionString
            .version()
        let version = Version("15.0.0")
        let deviceName = "iPhone 11"
        let arguments = ["-arg1", "--arg2", "SomeArgument"]
        targetRunner
            .runTargetStub = {
                _, _workspacePath, _schemeName, _configuration, _minVersion, _version, _deviceName,
                    _arguments in
                // Then
                #expect(_workspacePath == workspacePath)
                #expect(_schemeName == schemeName)
                #expect(_configuration == configuration)
                #expect(_minVersion == minVersion)
                #expect(_version == version)
                #expect(_deviceName == deviceName)
                #expect(_arguments == arguments)
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
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
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
            targetBuilder.buildTargetStub = { _, _, _, _, _, _, _, _, _, _, _, _ in }
            targetRunner.assertCanRunTargetStub = { _ in throw TestError() }

            // Then
            await #expect(
                throws: TestError.self
            ) { try await subject.run() }
        }
    }

    @Test
    func test_run_share_link_when_app_build_artifact_not_found() async throws {
        // Given
        given(getPreviewService)
            .getPreview(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(.test(url: .test()))

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(nil)

        // When / Then
        await #expect(
            throws: RunCommandServiceError.appNotFound(
                "https://tuist.io/tuist/tuist/preview/some-id"
            )
        ) {
            try await subject.run(
                runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!)
            )
        }
    }

    func test_run_share_link_when_version_is_invalid() async throws {
        // When / Then
        await #expect(
            throws: RunCommandServiceError.invalidVersion("invalid-version")
        ) {
            try await subject.run(
                runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!),
                osVersion: "invalid-version"
            )
        }
    }

    @Test
    func test_run_share_link_runs_app() async throws {
        try await withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                given(getPreviewService)
                    .getPreview(
                        .any,
                        fullHandle: .any,
                        serverURL: .any
                    )
                    .willReturn(.test())

                let downloadedArchive = temporaryDirectory.appending(component: "archive")

                given(remoteArtifactDownloader)
                    .download(url: .any)
                    .willReturn(downloadedArchive)

                let fileUnarchiver = MockFileUnarchiving()
                given(fileArchiverFactory)
                    .makeFileUnarchiver(for: .any)
                    .willReturn(fileUnarchiver)

                let unarchivedPath = temporaryDirectory.appending(component: "unarchived")

                given(fileUnarchiver)
                    .unzip()
                    .willReturn(unarchivedPath)

                try await fileSystem.makeDirectory(at: unarchivedPath)
                try await fileSystem.touch(unarchivedPath.appending(component: "App.app"))

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
                    runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!)
                )

                // Then
                verify(appRunner)
                    .runApp(
                        .value([appBundle]),
                        version: .value(nil),
                        device: .value(nil)
                    )
                    .called(1)
            }
        }
    }

    @Test
    func test_run_preview_with_specifier_runs_app() async throws {
        try await withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                given(getPreviewService)
                    .getPreview(
                        .any,
                        fullHandle: .any,
                        serverURL: .any
                    )
                    .willReturn(.test())

                let downloadedArchive = temporaryDirectory.appending(component: "archive")

                given(remoteArtifactDownloader)
                    .download(url: .any)
                    .willReturn(downloadedArchive)

                let fileUnarchiver = MockFileUnarchiving()
                given(fileArchiverFactory)
                    .makeFileUnarchiver(for: .any)
                    .willReturn(fileUnarchiver)

                let unarchivedPath = temporaryDirectory.appending(component: "unarchived")

                given(fileUnarchiver)
                    .unzip()
                    .willReturn(unarchivedPath)

                try await fileSystem.makeDirectory(at: unarchivedPath)
                try await fileSystem.touch(unarchivedPath.appending(component: "App.app"))

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

                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test(fullHandle: "tuist/tuist"))

                given(listPreviewsService)
                    .listPreviews(
                        displayName: .value("App"),
                        specifier: .value("latest"),
                        supportedPlatforms: .any,
                        page: .value(1),
                        pageSize: .value(1),
                        distinctField: .any,
                        fullHandle: .any,
                        serverURL: .any
                    )
                    .willReturn(
                        [
                            .test(),
                        ]
                    )

                // When
                try await subject.run(runnable: .specifier(displayName: "App", specifier: "latest"))

                // Then
                verify(appRunner)
                    .runApp(
                        .value([appBundle]),
                        version: .value(nil),
                        device: .value(nil)
                    )
                    .called(1)
            }
        }
    }

    @Test
    func test_run_preview_with_specifier_when_full_handle_is_missing() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        // When / Then
        await #expect(
            throws: RunCommandServiceError.missingFullHandle(
                displayName: "App", specifier: "latest"
            )
        ) {
            try await subject.run(runnable: .specifier(displayName: "App", specifier: "latest"))
        }
    }

    func test_run_preview_with_specifier_when_preview_is_not_found() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(listPreviewsService)
            .listPreviews(
                displayName: .value("App"),
                specifier: .value("latest"),
                supportedPlatforms: .any,
                page: .value(1),
                pageSize: .value(1),
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn([])

        // When / Then
        await #expect(
            throws: RunCommandServiceError.previewNotFound(displayName: "App", specifier: "latest")
        ) {
            try await subject.run(runnable: .specifier(displayName: "app", specifier: "latest"))
        }
    }

    @Test
    func test_run_share_link_runs_ipa() async throws {
        try await withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                given(getPreviewService)
                    .getPreview(
                        .any,
                        fullHandle: .any,
                        serverURL: .any
                    )
                    .willReturn(.test())

                let downloadedArchive = temporaryDirectory.appending(component: "archive")

                given(remoteArtifactDownloader)
                    .download(url: .any)
                    .willReturn(downloadedArchive)

                let fileUnarchiver = MockFileUnarchiving()
                given(fileArchiverFactory)
                    .makeFileUnarchiver(for: .any)
                    .willReturn(fileUnarchiver)

                let unarchivedPath = temporaryDirectory.appending(component: "unarchived")

                given(fileUnarchiver)
                    .unzip()
                    .willReturn(unarchivedPath)

                try await fileSystem.makeDirectory(at: unarchivedPath)
                // The `.app` bundle is nested in an `Payload` directory in the `.ipa` archive
                try await fileSystem.makeDirectory(
                    at: unarchivedPath.appending(components: "Payload", "App.app")
                )

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
                    runnable: .url(URL(string: "https://tuist.io/tuist/tuist/preview/some-id")!)
                )

                // Then
                verify(appRunner)
                    .runApp(
                        .value([appBundle]),
                        version: .value(nil),
                        device: .value(nil)
                    )
                    .called(1)
            }
        }
    }

    func test_run_share_link_runs_with_destination_and_version() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            given(getPreviewService)
                .getPreview(
                    .any,
                    fullHandle: .any,
                    serverURL: .any
                )
                .willReturn(.test())

            let downloadedArchive = temporaryDirectory.appending(component: "archive")

            given(remoteArtifactDownloader)
                .download(url: .any)
                .willReturn(downloadedArchive)

            let fileUnarchiver = MockFileUnarchiving()
            given(fileArchiverFactory)
                .makeFileUnarchiver(for: .any)
                .willReturn(fileUnarchiver)

            let unarchivedPath = temporaryDirectory.appending(component: "unarchived")

            given(fileUnarchiver)
                .unzip()
                .willReturn(unarchivedPath)

            try await fileSystem.touch(unarchivedPath.appending(component: "App.app"))

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
}

extension RunCommandService {
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
