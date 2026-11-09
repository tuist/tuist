import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer

@testable import TuistTestCommand

struct TestShowCommandServiceTests {
    private let getTestRunService = MockGetTestRunServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestShowCommandService

    init() {
        subject = TestShowCommandService(
            getTestRunService: getTestRunService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment()) func run_when_full_handle_is_not_passed_and_absent_in_config() async throws {
        // Given
        let tuist = Tuist.test(fullHandle: nil)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        // When/Then
        await #expect(throws: TestShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testRunId: "run-id",
                path: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_with_json_output() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testRun = ServerTestRun.test(
            macosVersion: "14.0",
            scheme: "App"
        )
        given(getTestRunService).getTestRun(
            fullHandle: .value(fullHandle),
            testRunId: .value("run-123"),
            serverURL: .value(serverURL)
        ).willReturn(testRun)

        // When
        try await subject.run(
            project: nil,
            testRunId: "run-123",
            path: nil,
            json: true
        )

        // Then
        #expect(ui().contains("run-id"))
        #expect(ui().contains("success"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_text_output() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testRun = ServerTestRun.test(
            avgTestDuration: 150,
            deviceName: "MacBook Pro (16-inch, 2021)",
            duration: 2500,
            failedTestCount: 3,
            flakyTestCount: 1,
            gitBranch: "feature/auth",
            gitCommitSha: "abc1234",
            isCi: true,
            isFlaky: true,
            macosVersion: "14.0",
            scheme: "App",
            status: .failure,
            totalTestCount: 100,
            xcodeVersion: "15.0"
        )
        given(getTestRunService).getTestRun(
            fullHandle: .value(fullHandle),
            testRunId: .value("run-456"),
            serverURL: .value(serverURL)
        ).willReturn(testRun)

        // When
        try await subject.run(
            project: nil,
            testRunId: "run-456",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("Test Run (failed)"))
        #expect(ui().contains("Result"))
        #expect(ui().contains("failure"))
        #expect(ui().contains("2.50s"))
        #expect(ui().contains("Flaky:        Yes"))
        #expect(ui().contains("Test Cases"))
        #expect(ui().contains("Total:        100"))
        #expect(ui().contains("Failed:       3"))
        #expect(ui().contains("Flaky:        1"))
        #expect(ui().contains("Avg Duration: 150ms"))
        #expect(ui().contains("Environment"))
        #expect(ui().contains("Device:       MacBook Pro (16-inch, 2021)"))
        #expect(ui().contains("macOS:        14.0"))
        #expect(ui().contains("Xcode:        15.0"))
        #expect(ui().contains("Context"))
        #expect(ui().contains("CI:           Yes"))
        #expect(ui().contains("Scheme:       App"))
        #expect(ui().contains("feature/auth"))
        #expect(ui().contains("abc1234"))
        #expect(ui().contains("IDs"))
        #expect(ui().contains("Run:          run-id"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora) func run_with_explicit_project_handle() async throws {
        // Given
        let configFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let explicitFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: configFullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testRun = ServerTestRun.test()
        given(getTestRunService).getTestRun(
            fullHandle: .value(explicitFullHandle),
            testRunId: .value("run-123"),
            serverURL: .value(serverURL)
        ).willReturn(testRun)

        // When
        try await subject.run(
            project: explicitFullHandle,
            testRunId: "run-123",
            path: nil,
            json: false
        )

        // Then
        verify(getTestRunService).getTestRun(
            fullHandle: .value(explicitFullHandle),
            testRunId: .any,
            serverURL: .any
        ).called(1)
    }
}
