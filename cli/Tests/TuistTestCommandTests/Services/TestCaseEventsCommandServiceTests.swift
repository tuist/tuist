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

struct TestCaseEventsCommandServiceTests {
    private let getTestCaseService = MockGetTestCaseServicing()
    private let listTestCaseEventsService = MockListTestCaseEventsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseEventsCommandService

    init() {
        subject = TestCaseEventsCommandService(
            getTestCaseService: getTestCaseService,
            listTestCaseEventsService: listTestCaseEventsService,
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
        await #expect(throws: TestCaseEventsCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testCaseIdentifier: "test-case-id",
                path: nil,
                page: nil,
                pageSize: nil,
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
        let eventsResponse = Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload(
            events: [
                ServerTestCaseEvent.test(eventType: .marked_flaky, insertedAt: 1_700_000_000),
                ServerTestCaseEvent.test(eventType: .first_run, insertedAt: 1_699_000_000),
            ],
            pagination_metadata: .init(
                has_next_page: false,
                has_previous_page: false,
                page_size: 20,
                total_count: 2
            )
        )
        given(listTestCaseEventsService).listTestCaseEvents(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-1"),
            page: .value(nil),
            pageSize: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(eventsResponse)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-1",
            path: nil,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        #expect(ui().contains("marked_flaky"))
        #expect(ui().contains("first_run"))
        #expect(ui().contains("1700000000"))
        #expect(ui().contains("1699000000"))
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
        let eventsResponse = Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload(
            events: [
                ServerTestCaseEvent.test(eventType: .quarantined, insertedAt: 1_700_000_000),
            ],
            pagination_metadata: .init(
                has_next_page: false,
                has_previous_page: false,
                page_size: 20,
                total_count: 1
            )
        )
        given(listTestCaseEventsService).listTestCaseEvents(
            fullHandle: .value(fullHandle),
            testCaseId: .value("tc-2"),
            page: .value(nil),
            pageSize: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(eventsResponse)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "tc-2",
            path: nil,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("Events"))
        #expect(ui().contains("Quarantined (automatic)"))
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_with_name_identifier_resolves_to_id() async throws {
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
            moduleName: .value("AuthTests"),
            name: .value("testLogin()"),
            suiteName: .value("LoginSuite"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)
        let eventsResponse = Operations.listTestCaseEvents.Output.Ok.Body.jsonPayload(
            events: [],
            pagination_metadata: .init(
                has_next_page: false,
                has_previous_page: false,
                page_size: 20,
                total_count: 0
            )
        )
        given(listTestCaseEventsService).listTestCaseEvents(
            fullHandle: .value(fullHandle),
            testCaseId: .value("resolved-tc-id"),
            page: .value(nil),
            pageSize: .value(nil),
            serverURL: .value(serverURL)
        ).willReturn(eventsResponse)

        // When
        try await subject.run(
            project: nil,
            testCaseIdentifier: "AuthTests/LoginSuite/testLogin()",
            path: nil,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        verify(listTestCaseEventsService).listTestCaseEvents(
            fullHandle: .any,
            testCaseId: .value("resolved-tc-id"),
            page: .any,
            pageSize: .any,
            serverURL: .any
        ).called(1)
        #expect(ui().contains("total_count"))
        #expect(ui().contains("0"))
    }
}
