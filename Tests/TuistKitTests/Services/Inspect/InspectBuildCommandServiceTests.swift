import FileSystem
import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph
import TuistSupportTesting
import ServiceContextModule

@testable import TuistKit

@Suite(.mocked)
struct InspectBuildCommandServiceTests {
    private let subject: InspectBuildCommandService
    private let ciChecker = MockCIChecking()
    private let configLoader = MockConfigLoading()
    private let xcactivityParser = MockXCActivityParsing()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let fileSystem = FileSystem()
    private let createBuildService = MockCreateBuildServicing()
    private let machineEnvironment = MockMachineEnvironmentRetrieving()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let backgroundProcessRunner = MockBackgroundProcessRunning()
    private let dateService = MockDateServicing()
    private let serverURLService = MockServerURLServicing()

    init() {
        subject = InspectBuildCommandService(
            derivedDataLocator: derivedDataLocator,
            fileSystem: fileSystem,
            ciChecker: ciChecker,
            machineEnvironment: machineEnvironment,
            xcodeBuildController: xcodeBuildController,
            createBuildService: createBuildService,
            configLoader: configLoader,
            xcactivityParser: xcactivityParser,
            backgroundProcessRunner: backgroundProcessRunner,
            dateService: dateService,
            serverURLService: serverURLService
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(createBuildService)
            .createBuild(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                duration: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                scheme: .any,
                xcodeVersion: .any,
                status: .any
            )
            .willReturn()

        given(ciChecker)
            .isCI()
            .willReturn(false)

        given(machineEnvironment)
            .modelIdentifier()
            .willReturn("Mac15,3")

        given(machineEnvironment)
            .macOSVersion
            .willReturn("13.2.0")

        given(xcodeBuildController)
            .version()
            .willReturn(Version(16, 0, 0))

        ServiceContext.current!.testEnvironment?.tuistVariables = ["TUIST_INSPECT_BUILD_WAIT": "YES"]
        ServiceContext.current!.testEnvironment?.schemeName = "App"

        given(dateService)
            .now()
            .willReturn(
                Date(timeIntervalSinceReferenceDate: 20)
            )
    }

    @Test
    func test_createsBuild() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") { temporaryDirectory in
            // Given
            let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
            ServiceContext.current!.testEnvironment?.workspacePath =  projectPath

            let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
            given(derivedDataLocator)
                .locate(for: .any)
                .willReturn(derivedDataPath)
            let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
            try await fileSystem.makeDirectory(at: buildLogsPath)
            try await fileSystem.writeAsPlist(
                LogStoreManifest(
                    logs: [
                        "id": ActivityLog(
                            fileName: "id.xcactivitylog",
                            timeStartedRecording: 10,
                            timeStoppedRecording: 20
                        ),
                    ]
                ),
                at: buildLogsPath.appending(component: "LogStoreManifest.plist")
            )
            given(xcactivityParser)
                .parse(.any)
                .willReturn(
                    .test(
                        buildStep: .test(
                            errorCount: 1
                        )
                    )
                )

            // When
            try await subject.run(path: nil)

            // Then
            verify(createBuildService)
                .createBuild(
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .any,
                    id: .any,
                    duration: .value(10000),
                    isCI: .value(false),
                    modelIdentifier: .value("Mac15,3"),
                    macOSVersion: .value("13.2.0"),
                    scheme: .value("App"),
                    xcodeVersion: .value("16.0.0"),
                    status: .value(.failure)
                )
                .called(1)
        }
    }

    @Test
    func test_when_should_not_wait() async throws {
        // Given
        ServiceContext.current!.testEnvironment?.tuistVariables = [:]
        ServiceContext.current!.testEnvironment?.workspacePath =  "/tmp/path"
        given(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(
                .any,
                environment: .matching {
                    $0["TUIST_INSPECT_BUILD_WAIT"] == "YES"
                }
            )
            .called(1)
    }

    func test_createsBuild_with_path_from_cli() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") { temporaryDirectory in
            // Given
            let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
            try await fileSystem.makeDirectory(at: projectPath)
            ServiceContext.current!.testEnvironment?.tuistVariables = [:]
            ServiceContext.current!.testEnvironment?.workspacePath =  nil

            let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
            given(derivedDataLocator)
                .locate(for: .any)
                .willReturn(derivedDataPath)
            let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
            try await fileSystem.makeDirectory(at: buildLogsPath)
            try await fileSystem.writeAsPlist(
                LogStoreManifest(
                    logs: [
                        "id": ActivityLog(
                            fileName: "id.xcactivitylog",
                            timeStartedRecording: 10,
                            timeStoppedRecording: 20
                        ),
                    ]
                ),
                at: buildLogsPath.appending(component: "LogStoreManifest.plist")
            )
            given(xcactivityParser)
                .parse(.any)
                .willReturn(.test())

            // When / Then
            try await subject.run(path: temporaryDirectory.pathString)
        }
    }

    @Test
    func test_createsBuild_with_path_from_cli_for_xcworkspace() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") { temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            try await fileSystem.makeDirectory(at: workspacePath)
            let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
            try await fileSystem.makeDirectory(at: projectPath)
            ServiceContext.current!.testEnvironment?.workspacePath =  nil
            
            let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
            given(derivedDataLocator)
                .locate(for: .any)
                .willReturn(derivedDataPath)
            let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
            try await fileSystem.makeDirectory(at: buildLogsPath)
            try await fileSystem.writeAsPlist(
                LogStoreManifest(
                    logs: [
                        "id": ActivityLog(
                            fileName: "id.xcactivitylog",
                            timeStartedRecording: 10,
                            timeStoppedRecording: 20
                        ),
                    ]
                ),
                at: buildLogsPath.appending(component: "LogStoreManifest.plist")
            )
            given(xcactivityParser)
                .parse(.any)
                .willReturn(.test())

            // When
            try await subject.run(path: temporaryDirectory.pathString)

            // Then
            verify(derivedDataLocator)
                .locate(for: .value(workspacePath))
                .called(1)
        }
    }

    @Test
    func test_when_no_project_exists_at_a_given_path() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") { temporaryDirectory in
            // Given
            ServiceContext.current!.testEnvironment?.workspacePath =  nil

            // When / Then
            await #expect(
                throws: InspectBuildCommandServiceError.projectNotFound(
                    temporaryDirectory
                )
            ) {
                try await subject.run(path: temporaryDirectory.pathString)
            }
        }
    }

    @Test
    func test_when_no_logs_exist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") { temporaryDirectory in
            // Given
            let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
            ServiceContext.current!.testEnvironment?.workspacePath =  projectPath
            
            let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
            given(derivedDataLocator)
                .locate(for: .any)
                .willReturn(derivedDataPath)

            // When / Then
            await #expect(
                throws: InspectBuildCommandServiceError.noBuildLogFound(
                    buildLogsPath: derivedDataPath.appending(components: "Logs", "Build"),
                    projectPath: projectPath
                )
            ) {
                try await subject.run(path: nil)
            }
        }
    }

    @Test
    func test_when_full_handle_not_specified() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") { temporaryDirectory in
            // Given
            let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
            try await fileSystem.makeDirectory(at: projectPath)
            ServiceContext.current!.testEnvironment?.workspacePath =  nil
            
            let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
            given(derivedDataLocator)
                .locate(for: .any)
                .willReturn(derivedDataPath)
            let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
            try await fileSystem.makeDirectory(at: buildLogsPath)
            try await fileSystem.writeAsPlist(
                LogStoreManifest(
                    logs: [
                        "id": ActivityLog(
                            fileName: "id.xcactivitylog",
                            timeStartedRecording: 10,
                            timeStoppedRecording: 20
                        ),
                    ]
                ),
                at: buildLogsPath.appending(component: "LogStoreManifest.plist")
            )
            given(xcactivityParser)
                .parse(.any)
                .willReturn(.test())
            configLoader.reset()
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: nil))

            // When / Then
            await #expect(
                throws: InspectBuildCommandServiceError.missingFullHandle
            ) {
                try await subject.run(path: projectPath.parentDirectory.pathString)
            }
        }
    }
}
