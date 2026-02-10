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

struct TestCaseRunShowCommandServiceTests {
    private let getTestCaseRunService = MockGetTestCaseRunServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseRunShowCommandService

    init() {
        subject = TestCaseRunShowCommandService(
            getTestCaseRunService: getTestCaseRunService,
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
        await #expect(throws: TestCaseRunShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testCaseRunId: "run-id",
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
        let testCaseRun = ServerTestCaseRun.test(
            moduleName: "AuthTests",
            name: "testLogin()"
        )
        given(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(fullHandle),
            testCaseRunId: .value("run-123"),
            serverURL: .value(serverURL)
        ).willReturn(testCaseRun)

        // When
        try await subject.run(
            project: nil,
            testCaseRunId: "run-123",
            path: nil,
            json: true
        )

        // Then
        #expect(ui().contains("testLogin()"))
        #expect(ui().contains("AuthTests"))
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
        let testCaseRun = ServerTestCaseRun.test(
            duration: 2500,
            gitBranch: "feature/auth",
            gitCommitSha: "abc1234",
            isCi: true,
            isFlaky: true,
            moduleName: "AppTests",
            name: "testFlaky()",
            scheme: "App",
            status: .failure,
            suiteName: "FlakyTests"
        )
        given(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(fullHandle),
            testCaseRunId: .value("run-456"),
            serverURL: .value(serverURL)
        ).willReturn(testCaseRun)

        // When
        try await subject.run(
            project: nil,
            testCaseRunId: "run-456",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("testFlaky()"))
        #expect(ui().contains("AppTests"))
        #expect(ui().contains("FlakyTests"))
        #expect(ui().contains("failure"))
        #expect(ui().contains("2.50s"))
        #expect(ui().contains("CI: Yes"))
        #expect(ui().contains("Flaky: Yes"))
        #expect(ui().contains("feature/auth"))
        #expect(ui().contains("abc1234"))
        #expect(ui().contains("App"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_failures() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCaseRun = ServerTestCaseRun.test(
            failures: [
                .init(
                    issue_type: "assertionFailure",
                    line_number: 42,
                    message: "Expected true but got false",
                    path: "Tests/AppTests/LoginTests.swift"
                ),
            ],
            status: .failure
        )
        given(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(fullHandle),
            testCaseRunId: .value("run-fail"),
            serverURL: .value(serverURL)
        ).willReturn(testCaseRun)

        // When
        try await subject.run(
            project: nil,
            testCaseRunId: "run-fail",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("Failures"))
        #expect(ui().contains("assertionFailure"))
        #expect(ui().contains("Tests/AppTests/LoginTests.swift:42"))
        #expect(ui().contains("Expected true but got false"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_repetitions() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCaseRun = ServerTestCaseRun.test(
            isFlaky: true,
            repetitions: [
                .init(duration: 500, repetition_number: 1, status: .failure),
                .init(duration: 600, repetition_number: 2, status: .success),
            ]
        )
        given(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(fullHandle),
            testCaseRunId: .value("run-rep"),
            serverURL: .value(serverURL)
        ).willReturn(testCaseRun)

        // When
        try await subject.run(
            project: nil,
            testCaseRunId: "run-rep",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("Repetitions"))
        #expect(ui().contains("#1: failure"))
        #expect(ui().contains("#2: success"))
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
        let testCaseRun = ServerTestCaseRun.test()
        given(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(explicitFullHandle),
            testCaseRunId: .value("run-123"),
            serverURL: .value(serverURL)
        ).willReturn(testCaseRun)

        // When
        try await subject.run(
            project: explicitFullHandle,
            testCaseRunId: "run-123",
            path: nil,
            json: false
        )

        // Then
        verify(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(explicitFullHandle),
            testCaseRunId: .any,
            serverURL: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_without_suite() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCaseRun = ServerTestCaseRun.test(
            moduleName: "CoreTests",
            name: "testNoSuite()",
            suiteName: nil
        )
        given(getTestCaseRunService).getTestCaseRun(
            fullHandle: .value(fullHandle),
            testCaseRunId: .value("run-no-suite"),
            serverURL: .value(serverURL)
        ).willReturn(testCaseRun)

        // When
        try await subject.run(
            project: nil,
            testCaseRunId: "run-no-suite",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("testNoSuite()"))
        #expect(ui().contains("CoreTests"))
        #expect(!ui().contains("Suite:"))
    }
}
