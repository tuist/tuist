import Foundation
import Mockable
import Testing
import TuistCore
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

@Suite
struct TestCaseListServiceTests {
    private let listTestCasesService = MockListTestCasesServicing()
    private let subject: TestCaseListService
    private let fullHandle = "org/project"
    private let serverURL = URL(string: "https://tuist.dev")!

    init() {
        subject = TestCaseListService(listTestCasesService: listTestCasesService)
    }

    @Test(.withMockedDependencies())
    func listAllTestCases_propagatesFetchErrors() async throws {
        let underlying = NSError(domain: "test", code: 500)
        given(listTestCasesService)
            .listTestCases(
                fullHandle: .any, serverURL: .any, flaky: .any,
                quarantined: .any, state: .any, page: .any, pageSize: .any
            )
            .willThrow(underlying)

        await #expect(throws: NSError.self) {
            _ = try await subject.listAllTestCases(
                fullHandle: fullHandle, serverURL: serverURL, state: .muted
            )
        }
    }

    @Test(.withMockedDependencies())
    func listAllTestCases_passesStateFilterThrough_andMapsToIdentifiers() async throws {
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
                    state: "muted",
                    suite: .test(name: "FooSuite")
                ),
                .test(id: "2", module: .test(name: "CoreTests"), name: "testBar()", state: "muted"),
            ]
        )

        given(listTestCasesService)
            .listTestCases(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                flaky: .value(nil),
                quarantined: .value(nil),
                state: .value(.muted),
                page: .value(1),
                pageSize: .value(500)
            )
            .willReturn(mutedResponse)

        let result = try await subject.listAllTestCases(
            fullHandle: fullHandle, serverURL: serverURL, state: .muted
        )

        #expect(result == [
            try TestIdentifier(target: "AppTests", class: "FooSuite", method: "testFoo()"),
            try TestIdentifier(target: "CoreTests", class: nil, method: "testBar()"),
        ])
    }

    @Test(.withMockedDependencies())
    func listAllTestCases_paginatesThroughAllPages() async throws {
        let page1Response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1, has_next_page: true, has_previous_page: false,
                page_size: 500, total_count: 3, total_pages: 2
            ),
            test_cases: [
                .test(
                    id: "1",
                    module: .test(name: "AppTests"),
                    name: "testFirst()",
                    state: "skipped",
                    suite: .test(name: "FirstSuite")
                ),
                .test(
                    id: "2",
                    module: .test(name: "AppTests"),
                    name: "testSecond()",
                    state: "skipped",
                    suite: .test(name: "SecondSuite")
                ),
            ]
        )
        let page2Response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 2, has_next_page: false, has_previous_page: true,
                page_size: 500, total_count: 3, total_pages: 2
            ),
            test_cases: [
                .test(
                    id: "3",
                    module: .test(name: "CoreTests"),
                    name: "testThird()",
                    state: "skipped",
                    suite: .test(name: "ThirdSuite")
                ),
            ]
        )

        given(listTestCasesService)
            .listTestCases(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                flaky: .value(nil),
                quarantined: .value(nil),
                state: .value(.skipped),
                page: .value(1),
                pageSize: .value(500)
            )
            .willReturn(page1Response)

        given(listTestCasesService)
            .listTestCases(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                flaky: .value(nil),
                quarantined: .value(nil),
                state: .value(.skipped),
                page: .value(2),
                pageSize: .value(500)
            )
            .willReturn(page2Response)

        let result = try await subject.listAllTestCases(
            fullHandle: fullHandle, serverURL: serverURL, state: .skipped
        )

        #expect(result == [
            try TestIdentifier(target: "AppTests", class: "FirstSuite", method: "testFirst()"),
            try TestIdentifier(target: "AppTests", class: "SecondSuite", method: "testSecond()"),
            try TestIdentifier(target: "CoreTests", class: "ThirdSuite", method: "testThird()"),
        ])
    }
}
