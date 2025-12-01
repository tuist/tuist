import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistLoader
import TuistProcess
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import TuistXCResultService

@testable import TuistKit

struct InspectTestCommandServiceTests {
    private let subject: InspectTestCommandService
    private let configLoader = MockConfigLoading()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let fileSystem = FileSystem()
    private let xcResultService = MockXCResultServicing()
    private let xcodeProjectOrWorkspacePathLocator = MockXcodeProjectOrWorkspacePathLocating()
    private let inspectResultBundleService = MockInspectResultBundleServicing()
    private let backgroundProcessRunner = MockBackgroundProcessRunning()

    init() throws {
        subject = InspectTestCommandService(
            derivedDataLocator: derivedDataLocator,
            fileSystem: fileSystem,
            xcResultService: xcResultService,
            xcodeProjectOrWorkspacePathLocator: xcodeProjectOrWorkspacePathLocator,
            inspectResultBundleService: inspectResultBundleService,
            configLoader: configLoader,
            backgroundProcessRunner: backgroundProcessRunner
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(inspectResultBundleService)
            .inspectResultBundle(resultBundlePath: .any, projectDerivedDataDirectory: .any, config: .any)
            .willReturn(
                Components.Schemas.RunsTest(
                    duration: 1000,
                    id: "test-id",
                    project_id: 1,
                    _type: .test,
                    url: "https://tuist.dev/tuist/tuist/runs/test-id"
                )
            )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_with_result_bundle_path() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let resultBundlePath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: resultBundlePath)

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["TUIST_INSPECT_TEST_WAIT"] = "YES"

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(temporaryDirectory))
            .willReturn(temporaryDirectory.appending(component: "App.xcodeproj"))

        // When
        try await subject.run(
            path: temporaryDirectory.pathString,
            resultBundlePath: resultBundlePath.pathString
        )

        // Then
        verify(inspectResultBundleService)
            .inspectResultBundle(
                resultBundlePath: .value(resultBundlePath),
                projectDerivedDataDirectory: .value(nil),
                config: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_finds_most_recent_result_bundle() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["TUIST_INSPECT_TEST_WAIT"] = "YES"

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(temporaryDirectory))
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .value(projectPath))
            .willReturn(derivedDataPath)

        let resultBundlePath = derivedDataPath.appending(components: "Logs", "Test", "Test.xcresult")
        given(xcResultService)
            .mostRecentXCResultFile(projectDerivedDataDirectory: .value(derivedDataPath))
            .willReturn(resultBundlePath)

        // When
        try await subject.run(path: temporaryDirectory.pathString)

        // Then
        verify(inspectResultBundleService)
            .inspectResultBundle(
                resultBundlePath: .value(resultBundlePath),
                projectDerivedDataDirectory: .value(derivedDataPath),
                config: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_with_derived_data_path() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["TUIST_INSPECT_TEST_WAIT"] = "YES"

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(temporaryDirectory))
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "custom-derived-data")
        let resultBundlePath = derivedDataPath.appending(components: "Logs", "Test", "Test.xcresult")
        given(xcResultService)
            .mostRecentXCResultFile(projectDerivedDataDirectory: .value(derivedDataPath))
            .willReturn(resultBundlePath)

        // When
        try await subject.run(
            path: temporaryDirectory.pathString,
            derivedDataPath: derivedDataPath.pathString
        )

        // Then
        verify(derivedDataLocator)
            .locate(for: .any)
            .called(0)

        verify(inspectResultBundleService)
            .inspectResultBundle(
                resultBundlePath: .value(resultBundlePath),
                projectDerivedDataDirectory: .value(derivedDataPath),
                config: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func run_throws_when_no_result_bundle_found() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["TUIST_INSPECT_TEST_WAIT"] = "YES"

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(temporaryDirectory))
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .value(projectPath))
            .willReturn(derivedDataPath)

        given(xcResultService)
            .mostRecentXCResultFile(projectDerivedDataDirectory: .value(derivedDataPath))
            .willReturn(nil)

        // When / Then
        await #expect(
            throws: InspectTestCommandServiceError.mostRecentResultBundleNotFound(derivedDataPath)
        ) {
            try await subject.run(path: temporaryDirectory.pathString)
        }
    }

    @Test(.withMockedEnvironment())
    func run_uses_current_working_directory_when_no_path_provided() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["TUIST_INSPECT_TEST_WAIT"] = "YES"
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()

        let projectPath = currentWorkingDirectory.appending(component: "App.xcodeproj")
        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(currentWorkingDirectory))
            .willReturn(projectPath)

        let derivedDataPath = currentWorkingDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .value(projectPath))
            .willReturn(derivedDataPath)

        let resultBundlePath = derivedDataPath.appending(components: "Logs", "Test", "Test.xcresult")
        given(xcResultService)
            .mostRecentXCResultFile(projectDerivedDataDirectory: .value(derivedDataPath))
            .willReturn(resultBundlePath)

        // When
        try await subject.run(path: nil)

        // Then
        verify(inspectResultBundleService)
            .inspectResultBundle(
                resultBundlePath: .value(resultBundlePath),
                projectDerivedDataDirectory: .value(derivedDataPath),
                config: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func when_should_not_wait() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables = [:]
        mockedEnvironment.workspacePath = "/tmp/path"
        mockedEnvironment.currentExecutablePathStub = "/usr/bin/tuist"

        given(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(
                .value(["/usr/bin/tuist", "inspect", "test"]),
                environment: .matching {
                    $0["TUIST_INSPECT_TEST_WAIT"] == "YES"
                }
            )
            .called(1)
    }
}
