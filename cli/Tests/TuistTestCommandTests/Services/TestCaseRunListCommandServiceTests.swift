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

struct TestCaseRunListCommandServiceTests {
    private let getTestCaseService = MockGetTestCaseServicing()
    private let listTestCaseRunsService = MockListTestCaseRunsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseRunListCommandService

    init() {
        subject = TestCaseRunListCommandService(
            getTestCaseService: getTestCaseService,
            listTestCaseRunsService: listTestCaseRunsService,
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
        await #expect(throws: TestCaseRunListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                path: nil,
                testCaseIdentifier: "Module/TestCase",
                flaky: false,
                testRunId: nil,
                page: nil,
                pageSize: nil,
                json: false
            )
        })
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
                path: nil,
                testCaseIdentifier: "a/b/c/d",
                flaky: false,
                testRunId: nil,
                page: nil,
                pageSize: nil,
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
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value("ExampleSuite"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            testCaseRuns: [
                .test(duration: 1500, status: .success),
            ]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/ExampleSuite/testExample",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        #expect(ui().contains("success"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_empty_results() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("No test case runs found for AppTests/testExample"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_empty_results_and_flaky_filter() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AppTests"),
            name: .value("testFlaky"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(true),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testFlaky",
            flaky: true,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("No test case runs found for AppTests/testFlaky (flaky only)"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_three_part_identifier() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AppTests"),
            name: .value("testLogin"),
            suiteName: .value("AuthSuite"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [
            .test(status: .success),
        ])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/AuthSuite/testLogin",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        verify(getTestCaseService).getTestCaseByName(
            fullHandle: .any,
            moduleName: .value("AppTests"),
            name: .value("testLogin"),
            suiteName: .value("AuthSuite"),
            serverURL: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_two_part_identifier() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("CoreTests"),
            name: .value("testSomething"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [
            .test(status: .success),
        ])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "CoreTests/testSomething",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        verify(getTestCaseService).getTestCaseByName(
            fullHandle: .any,
            moduleName: .value("CoreTests"),
            name: .value("testSomething"),
            suiteName: .value(nil),
            serverURL: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_uuid_identifier() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [
            .test(status: .success),
        ])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("some-uuid-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "some-uuid-id",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            testCaseId: .value("some-uuid-id"),
            flaky: .any,
            testRunId: .any,
            page: .any,
            pageSize: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_custom_page_size() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            pageSize: 5,
            testCaseRuns: [.test()]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(5)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: 5,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            testCaseId: .any,
            flaky: .any,
            testRunId: .any,
            page: .any,
            pageSize: .value(5)
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_custom_page() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(fullHandle),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            currentPage: 3,
            totalPages: 5,
            hasPreviousPage: true,
            testCaseRuns: [.test()]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(3),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            testRunId: nil,
            page: 3,
            pageSize: nil,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            testCaseId: .any,
            flaky: .any,
            testRunId: .any,
            page: .value(3),
            pageSize: .any
        ).called(1)
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
        let testCase = ServerTestCase.test(id: "resolved-tc-id")
        given(getTestCaseService).getTestCaseByName(
            fullHandle: .value(explicitFullHandle),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(explicitFullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value("resolved-tc-id"),
            flaky: .value(nil),
            testRunId: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: explicitFullHandle,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            testRunId: nil,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(explicitFullHandle),
            serverURL: .any,
            testCaseId: .any,
            flaky: .any,
            testRunId: .any,
            page: .any,
            pageSize: .any
        ).called(1)
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_by_test_run_id() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            testCaseRuns: [
                .test(moduleName: "AppTests", name: "testLogin", status: .success),
                .test(id: "run-id-2", moduleName: "AppTests", name: "testLogout", status: .failure),
            ]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            testCaseId: .value(nil),
            flaky: .value(nil),
            testRunId: .value("test-run-uuid"),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: nil,
            flaky: false,
            testRunId: "test-run-uuid",
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        #expect(ui().contains("testLogin"))
        #expect(ui().contains("testLogout"))
    }
}
