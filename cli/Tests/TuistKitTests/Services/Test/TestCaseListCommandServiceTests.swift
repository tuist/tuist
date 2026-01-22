import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct TestCaseListCommandServiceTests {
    private let listTestCasesService = MockListTestCasesServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCaseListCommandService

    init() {
        subject = TestCaseListCommandService(
            listTestCasesService: listTestCasesService,
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
        await #expect(throws: TestCaseListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                path: nil,
                quarantined: false,
                flaky: false,
                skipTesting: false,
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 10,
                total_count: 1,
                total_pages: 1
            ),
            test_cases: [
                .init(
                    avg_duration: 150,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: false,
                    module: .init(id: UUID().uuidString, name: "AppTests"),
                    name: "testExample()",
                    suite: .init(id: UUID().uuidString, name: "ExampleTests"),
                    url: "https://tuist.dev/test-case/1"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: nil,
            pageSize: nil,
            json: true
        )

        // Then
        #expect(ui().contains("testExample()"))
        #expect(ui().contains("AppTests"))
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 10,
                total_count: 0,
                total_pages: 0
            ),
            test_cases: []
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("No test cases found for project \(fullHandle)"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_empty_results_and_filters() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 10,
                total_count: 0,
                total_pages: 0
            ),
            test_cases: []
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(true),
            quarantined: .value(true),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: true,
            flaky: true,
            skipTesting: false,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("No test cases found for project \(fullHandle) with filters: quarantined, flaky"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_skip_testing_flag() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 500,
                total_count: 2,
                total_pages: 1
            ),
            test_cases: [
                .init(
                    avg_duration: 100,
                    id: UUID().uuidString,
                    is_flaky: true,
                    is_quarantined: false,
                    module: .init(id: UUID().uuidString, name: "AppTests"),
                    name: "testFlaky()",
                    suite: .init(id: UUID().uuidString, name: "FlakyTests"),
                    url: "https://tuist.dev/test-case/1"
                ),
                .init(
                    avg_duration: 200,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: true,
                    module: .init(id: UUID().uuidString, name: "CoreTests"),
                    name: "testQuarantined()",
                    suite: nil,
                    url: "https://tuist.dev/test-case/2"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(500)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: true,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("-skip-testing AppTests/FlakyTests/testFlaky()"))
        #expect(ui().contains("-skip-testing CoreTests/testQuarantined()"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_skip_testing_flag_and_quarantined_filter() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 500,
                total_count: 1,
                total_pages: 1
            ),
            test_cases: [
                .init(
                    avg_duration: 200,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: true,
                    module: .init(id: UUID().uuidString, name: "CoreTests"),
                    name: "testQuarantined()",
                    suite: .init(id: UUID().uuidString, name: "QuarantinedTests"),
                    url: "https://tuist.dev/test-case/1"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(true),
            page: .value(1),
            pageSize: .value(500)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: true,
            flaky: false,
            skipTesting: true,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("-skip-testing CoreTests/QuarantinedTests/testQuarantined()"))
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 5,
                total_count: 1,
                total_pages: 1
            ),
            test_cases: [
                .init(
                    avg_duration: 100,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: false,
                    module: .init(id: UUID().uuidString, name: "AppTests"),
                    name: "testExample()",
                    suite: nil,
                    url: "https://tuist.dev/test-case/1"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(5)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: nil,
            pageSize: 5,
            json: false
        )

        // Then
        #expect(ui().contains("testExample()"))
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 2,
                has_next_page: false,
                has_previous_page: true,
                page_size: 10,
                total_count: 15,
                total_pages: 2
            ),
            test_cases: [
                .init(
                    avg_duration: 100,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: false,
                    module: .init(id: UUID().uuidString, name: "AppTests"),
                    name: "testPage2()",
                    suite: nil,
                    url: "https://tuist.dev/test-case/1"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(2),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: 2,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("testPage2()"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_empty_results_on_specific_page() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 5,
                has_next_page: false,
                has_previous_page: true,
                page_size: 10,
                total_count: 10,
                total_pages: 1
            ),
            test_cases: []
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(5),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: 5,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("No test cases found on page 5 for project \(fullHandle)"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_duration_formatting_milliseconds() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 10,
                total_count: 1,
                total_pages: 1
            ),
            test_cases: [
                .init(
                    avg_duration: 500,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: false,
                    module: .init(id: UUID().uuidString, name: "AppTests"),
                    name: "testFast()",
                    suite: nil,
                    url: "https://tuist.dev/test-case/1"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("500ms"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_with_duration_formatting_seconds() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 10,
                total_count: 1,
                total_pages: 1
            ),
            test_cases: [
                .init(
                    avg_duration: 2500,
                    id: UUID().uuidString,
                    is_flaky: false,
                    is_quarantined: false,
                    module: .init(id: UUID().uuidString, name: "AppTests"),
                    name: "testSlow()",
                    suite: nil,
                    url: "https://tuist.dev/test-case/1"
                ),
            ]
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        #expect(ui().contains("2.50s"))
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1,
                has_next_page: false,
                has_previous_page: false,
                page_size: 10,
                total_count: 0,
                total_pages: 0
            ),
            test_cases: []
        )
        given(listTestCasesService).listTestCases(
            fullHandle: .value(explicitFullHandle),
            serverURL: .value(serverURL),
            flaky: .value(nil),
            quarantined: .value(nil),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(response)

        // When
        try await subject.run(
            project: explicitFullHandle,
            path: nil,
            quarantined: false,
            flaky: false,
            skipTesting: false,
            page: nil,
            pageSize: nil,
            json: false
        )

        // Then
        verify(listTestCasesService).listTestCases(
            fullHandle: .value(explicitFullHandle),
            serverURL: .any,
            flaky: .any,
            quarantined: .any,
            page: .any,
            pageSize: .any
        ).called(1)
    }
}
