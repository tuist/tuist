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

struct TestCaseUpdateCommandServiceTests {
    private let getTestCaseService = MockGetTestCaseServicing()
    private let updateTestCaseService = MockUpdateTestCaseServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseUpdateCommandService

    init() {
        subject = TestCaseUpdateCommandService(
            getTestCaseService: getTestCaseService,
            updateTestCaseService: updateTestCaseService,
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
        await #expect(throws: TestCaseUpdateCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testCaseIdentifier: "test-case-id",
                state: .enabled,
                isFlaky: nil,
                path: nil,
                json: false
            )
        })
    }

    @Test(.withMockedEnvironment()) func run_when_neither_state_nor_flaky_provided() async throws {
        // When/Then
        await #expect(throws: TestCaseUpdateCommandServiceError.missingUpdateFields, performing: {
            try await subject.run(
                project: nil,
                testCaseIdentifier: "test-case-id",
                state: nil,
                isFlaky: nil,
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
        let updated = ServerUpdatedTestCase.test(
            module: .test(name: "AuthTests"),
            name: "testLogin()",
            state: .enabled
        )
        given(updateTestCaseService).updateTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("test-case-id"),
            state: .value(.enabled),
            isFlaky: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(updated)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "test-case-id",
            state: .enabled,
            isFlaky: nil,
            path: nil,
            json: true
        )

        // Then
        let payload = try #require(decodeJSON(ui()))
        #expect(payload["name"] as? String == "testLogin()")
        #expect((payload["module"] as? [String: Any])?["name"] as? String == "AuthTests")
        #expect(payload["state"] as? String == "enabled")
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
        let resolvedTestCase = ServerTestCase.test(
            id: "resolved-id",
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
        ).willReturn(resolvedTestCase)
        let updated = ServerUpdatedTestCase.test(
            id: "resolved-id",
            module: .test(name: "AuthTests"),
            name: "testLogin()",
            state: .muted
        )
        given(updateTestCaseService).updateTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("resolved-id"),
            state: .value(.muted),
            isFlaky: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(updated)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "AuthTests/LoginSuite/testLogin()",
            state: .muted,
            isFlaky: nil,
            path: nil,
            json: true
        )

        // Then
        let payload = try #require(decodeJSON(ui()))
        #expect(payload["name"] as? String == "testLogin()")
        #expect(payload["state"] as? String == "muted")
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
        let updated = ServerUpdatedTestCase.test(
            isFlaky: true,
            module: .test(name: "AppTests"),
            name: "testFlaky()",
            state: .muted,
            suite: .test(name: "FlakyTests"),
            url: "https://tuist.dev/some-test"
        )
        given(updateTestCaseService).updateTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-123"),
            state: .value(.muted),
            isFlaky: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(updated)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-123",
            state: .muted,
            isFlaky: nil,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("testFlaky()"))
        #expect(ui().contains("AppTests"))
        #expect(ui().contains("FlakyTests"))
        #expect(ui().contains("Flaky: Yes"))
        #expect(ui().contains("State: muted"))
        #expect(ui().contains("https://tuist.dev/some-test"))
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
        let updated = ServerUpdatedTestCase.test()
        given(updateTestCaseService).updateTestCase(
            fullHandle: .value(explicitFullHandle),
            testCaseId: .value("tc-123"),
            state: .value(.enabled),
            isFlaky: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(updated)

        // When
        try await subject.run(
            project: explicitFullHandle,
            testCaseIdentifier: "tc-123",
            state: .enabled,
            isFlaky: nil,
            path: nil,
            json: false
        )

        // Then
        verify(updateTestCaseService).updateTestCase(
            fullHandle: .value(explicitFullHandle),
            testCaseId: .any,
            state: .any,
            isFlaky: .any,
            serverURL: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_flaky_only_update() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let updated = ServerUpdatedTestCase.test(
            isFlaky: true,
            module: .test(name: "AuthTests"),
            name: "testLogin()",
            state: .enabled
        )
        given(updateTestCaseService).updateTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-123"),
            state: .value(nil),
            isFlaky: .value(true),
            serverURL: .value(serverURL)
        ).willReturn(updated)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-123",
            state: nil,
            isFlaky: true,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("Flaky: Yes"))
        verify(updateTestCaseService).updateTestCase(
            fullHandle: .any,
            testCaseId: .any,
            state: .value(nil),
            isFlaky: .value(true),
            serverURL: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_state_and_flaky_combined() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let updated = ServerUpdatedTestCase.test(
            isFlaky: false,
            module: .test(name: "AuthTests"),
            name: "testLogin()",
            state: .enabled
        )
        given(updateTestCaseService).updateTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-123"),
            state: .value(.enabled),
            isFlaky: .value(false),
            serverURL: .value(serverURL)
        ).willReturn(updated)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-123",
            state: .enabled,
            isFlaky: false,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains("State: enabled"))
        #expect(ui().contains("Flaky: No"))
        verify(updateTestCaseService).updateTestCase(
            fullHandle: .any,
            testCaseId: .any,
            state: .value(.enabled),
            isFlaky: .value(false),
            serverURL: .any
        ).called(1)
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
                state: .enabled,
                isFlaky: nil,
                path: nil,
                json: false
            )
        })
    }

    private func decodeJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
