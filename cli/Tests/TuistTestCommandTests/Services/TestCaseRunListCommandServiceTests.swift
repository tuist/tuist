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
    private let listTestCaseRunsService = MockListTestCaseRunsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseRunListCommandService

    init() {
        subject = TestCaseRunListCommandService(
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
        await #expect(throws: TestCaseRunListCommandServiceError.invalidIdentifier("justAName"), performing: {
            try await subject.run(
                project: nil,
                path: nil,
                testCaseIdentifier: "justAName",
                flaky: false,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            testCaseRuns: [
                .test(duration: 1500, status: .success),
            ]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value("ExampleSuite"),
            flaky: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/ExampleSuite/testExample",
            flaky: false,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            flaky: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testFlaky"),
            suiteName: .value(nil),
            flaky: .value(true),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testFlaky",
            flaky: true,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [
            .test(status: .success),
        ])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testLogin"),
            suiteName: .value("AuthSuite"),
            flaky: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/AuthSuite/testLogin",
            flaky: false,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            moduleName: .value("AppTests"),
            name: .value("testLogin"),
            suiteName: .value("AuthSuite"),
            flaky: .any,
            page: .any,
            pageSize: .any
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [
            .test(status: .success),
        ])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("CoreTests"),
            name: .value("testSomething"),
            suiteName: .value(nil),
            flaky: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "CoreTests/testSomething",
            flaky: false,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            moduleName: .value("CoreTests"),
            name: .value("testSomething"),
            suiteName: .value(nil),
            flaky: .any,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            pageSize: 5,
            testCaseRuns: [.test()]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            flaky: .value(nil),
            page: .value(1),
            pageSize: .value(5)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            page: nil,
            pageSize: 5,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            moduleName: .any,
            name: .any,
            suiteName: .any,
            flaky: .any,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(
            currentPage: 3,
            totalPages: 5,
            hasPreviousPage: true,
            testCaseRuns: [.test()]
        )
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            flaky: .value(nil),
            page: .value(3),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            page: 3,
            pageSize: nil,
            json: true
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .any,
            serverURL: .any,
            moduleName: .any,
            name: .any,
            suiteName: .any,
            flaky: .any,
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
        let response = Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test(testCaseRuns: [])
        given(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(explicitFullHandle),
            serverURL: .value(serverURL),
            moduleName: .value("AppTests"),
            name: .value("testExample"),
            suiteName: .value(nil),
            flaky: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: explicitFullHandle,
            path: nil,
            testCaseIdentifier: "AppTests/testExample",
            flaky: false,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        verify(listTestCaseRunsService).listTestCaseRuns(
            fullHandle: .value(explicitFullHandle),
            serverURL: .any,
            moduleName: .any,
            name: .any,
            suiteName: .any,
            flaky: .any,
            page: .any,
            pageSize: .any
        ).called(1)
    }
}
