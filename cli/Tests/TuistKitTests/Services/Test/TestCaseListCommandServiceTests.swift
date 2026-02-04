import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            testCases: [
                .test(name: "testExample()", moduleName: "AppTests", suiteName: "ExampleTests"),
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(testCases: [])
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(testCases: [])
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            pageSize: 500,
            testCases: [
                .test(name: "testFlaky()", moduleName: "AppTests", suiteName: "FlakyTests", isFlaky: true),
                .test(name: "testQuarantined()", moduleName: "CoreTests", isQuarantined: true),
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            pageSize: 500,
            testCases: [
                .test(name: "testQuarantined()", moduleName: "CoreTests", suiteName: "QuarantinedTests", isQuarantined: true),
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            pageSize: 5,
            testCases: [.test(name: "testExample()", moduleName: "AppTests")]
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            currentPage: 2,
            totalPages: 2,
            hasPreviousPage: true,
            testCases: [.test(name: "testPage2()", moduleName: "AppTests")]
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            currentPage: 5,
            hasPreviousPage: true,
            testCases: []
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            testCases: [.test(name: "testFast()", moduleName: "AppTests", avgDuration: 500)]
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(
            testCases: [.test(name: "testSlow()", moduleName: "AppTests", avgDuration: 2500)]
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
        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload.test(testCases: [])
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

extension Operations.listTestCases.Output.Ok.Body.jsonPayload {
    static func test(
        currentPage: Int = 1,
        pageSize: Int = 10,
        totalPages: Int = 1,
        hasNextPage: Bool = false,
        hasPreviousPage: Bool = false,
        testCases: [Components.Schemas.TestCase]
    ) -> Self {
        .init(
            pagination_metadata: .init(
                current_page: currentPage,
                has_next_page: hasNextPage,
                has_previous_page: hasPreviousPage,
                page_size: pageSize,
                total_count: testCases.count,
                total_pages: totalPages
            ),
            test_cases: testCases
        )
    }
}

extension Components.Schemas.TestCase {
    static func test(
        name: String,
        moduleName: String,
        suiteName: String? = nil,
        avgDuration: Int = 100,
        isFlaky: Bool = false,
        isQuarantined: Bool = false
    ) -> Self {
        .init(
            avg_duration: avgDuration,
            id: UUID().uuidString,
            is_flaky: isFlaky,
            is_quarantined: isQuarantined,
            module: .init(id: UUID().uuidString, name: moduleName),
            name: name,
            suite: suiteName.map { .init(id: UUID().uuidString, name: $0) },
            url: "https://tuist.dev/test-case/\(UUID().uuidString)"
        )
    }
}
