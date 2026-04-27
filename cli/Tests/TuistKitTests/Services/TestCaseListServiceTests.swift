import Foundation
import Mockable
import Testing
import TuistConfig
import TuistCore
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

@Suite
struct TestCaseListServiceTests {
    private let listTestCasesService = MockListTestCasesServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let subject: TestCaseListService

    init() {
        subject = TestCaseListService(
            listTestCasesService: listTestCasesService,
            serverEnvironmentService: serverEnvironmentService
        )
    }

    @Test(.withMockedDependencies())
    func listTestCases_returnsEmpty_whenFullHandleIsNil() async throws {
        let config = Tuist.test(fullHandle: nil)
        let result = try await subject.listTestCases(config: config, state: .muted)
        #expect(result.isEmpty)
    }

    @Test(.withMockedDependencies())
    func listTestCases_propagatesFetchErrors() async throws {
        let config = Tuist.test(fullHandle: "org/project")
        let serverURL = URL(string: "https://tuist.dev")!

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        let underlying = NSError(domain: "test", code: 500)
        given(listTestCasesService)
            .listTestCases(
                fullHandle: .any, serverURL: .any, flaky: .any,
                quarantined: .any, state: .any, page: .any, pageSize: .any
            )
            .willThrow(underlying)

        await #expect(throws: NSError.self) {
            _ = try await subject.listTestCases(config: config, state: .muted)
        }
    }

    @Test(.withMockedDependencies())
    func listTestCases_passesStateFilterThrough_andMapsToIdentifiers() async throws {
        let config = Tuist.test(fullHandle: "org/project")
        let serverURL = URL(string: "https://tuist.dev")!

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        let mutedResponse = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1, has_next_page: false, has_previous_page: false,
                page_size: 500, total_count: 2, total_pages: 1
            ),
            test_cases: [
                .test(
                    id: "1",
                    module: .test(name: "AppTests"),
                    name: "testFoo()",
                    state: .muted,
                    suite: .test(name: "FooSuite")
                ),
                .test(id: "2", module: .test(name: "CoreTests"), name: "testBar()", state: .muted),
            ]
        )

        given(listTestCasesService)
            .listTestCases(
                fullHandle: .value("org/project"),
                serverURL: .value(serverURL),
                flaky: .value(nil),
                quarantined: .value(nil),
                state: .value(.muted),
                page: .value(1),
                pageSize: .value(500)
            )
            .willReturn(mutedResponse)

        let result = try await subject.listTestCases(config: config, state: .muted)

        #expect(result == [
            try TestIdentifier(target: "AppTests", class: "FooSuite", method: "testFoo()"),
            try TestIdentifier(target: "CoreTests", class: nil, method: "testBar()"),
        ])
    }
}
