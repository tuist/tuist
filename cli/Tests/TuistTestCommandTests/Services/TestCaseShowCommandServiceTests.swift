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

struct TestCaseShowCommandServiceTests {
    private let getTestCaseService = MockGetTestCaseServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseShowCommandService

    init() {
        subject = TestCaseShowCommandService(
            getTestCaseService: getTestCaseService,
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
        await #expect(throws: TestCaseShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testCaseIdentifier: "test-case-id",
                path: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_with_json_output_and_uuid() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(
            module: .test(name: "AuthTests"),
            name: "testLogin()"
        )
        given(getTestCaseService).getTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("test-case-id"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "test-case-id",
            path: nil,
            json: true
        )

        // Then
        #expect(ui().contains("testLogin()"))
        #expect(ui().contains("AuthTests"))
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_with_json_output_and_name_identifier() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(
            module: .test(name: "AuthTests"),
            name: "testLogin()",
            suite: .test(name: "LoginSuite")
        )
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AuthTests"),
            name: .value("testLogin()"),
            suiteName: .value("LoginSuite"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "AuthTests/LoginSuite/testLogin()",
            path: nil,
            json: true
        )

        // Then
        #expect(ui().contains("testLogin()"))
        #expect(ui().contains("AuthTests"))
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_with_name_identifier_without_suite() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(
            module: .test(name: "CoreTests"),
            name: "testNoSuite()"
        )
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("CoreTests"),
            name: .value("testNoSuite()"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "CoreTests/testNoSuite()",
            path: nil,
            json: true
        )

        // Then
        #expect(ui().contains("testNoSuite()"))
        #expect(ui().contains("CoreTests"))
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
        let testCase = ServerTestCase.test(
            failedRuns: 3,
            flakinessRate: 12.5,
            isFlaky: true,
            module: .test(name: "AppTests"),
            name: "testFlaky()",
            reliabilityRate: 87.5,
            suite: .test(name: "FlakyTests"),
            totalRuns: 100
        )
        given(getTestCaseService).getTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-123"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-123",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("testFlaky()"))
        #expect(ui().contains("AppTests"))
        #expect(ui().contains("FlakyTests"))
        #expect(ui().contains("Flaky: Yes"))
        #expect(ui().contains("12.5%"))
        #expect(ui().contains("87.5%"))
        #expect(ui().contains("Total Runs: 100"))
        #expect(ui().contains("Failed Runs: 3"))
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
        let testCase = ServerTestCase.test()
        given(getTestCaseService).getTestCase(
            fullHandle: .value(explicitFullHandle),
            testCaseId: .value("tc-123"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        // When
        try await subject.run(
            project: explicitFullHandle,
            testCaseIdentifier: "tc-123",
            path: nil,
            json: false
        )

        // Then
        verify(getTestCaseService).getTestCase(
            fullHandle: .value(explicitFullHandle),
            testCaseId: .any,
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
        let testCase = ServerTestCase.test(
            module: .test(name: "CoreTests"),
            name: "testNoSuite()",
            suite: nil
        )
        given(getTestCaseService).getTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-456"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-456",
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("testNoSuite()"))
        #expect(ui().contains("CoreTests"))
        #expect(!ui().contains("Suite:"))
    }

    @Test(.withMockedEnvironment()) func run_with_invalid_identifier() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        // When/Then
        await #expect(throws: TestCaseIdentifierError.invalidIdentifier("a/b/c/d"), performing: {
            try await subject.run(
                project: nil,
                testCaseIdentifier: "a/b/c/d",
                path: nil,
                json: false
            )
        })
    }
}
