import Foundation
import Mockable
import TuistCore
import TuistServer

@Mockable
protocol TestCaseListServicing {
    /// Fetch all test cases for `fullHandle` matching the given state
    /// (e.g. `.muted` / `.skipped`) and return them as `TestIdentifier`s.
    ///
    /// Throws on network, decoding, or `TestIdentifier` construction
    /// errors — call sites decide how to react (warn the user and fall
    /// back to running all tests, or surface the error directly).
    func listAllTestCases(
        fullHandle: String,
        serverURL: URL,
        state: Operations.listTestCases.Input.Query.statePayload
    ) async throws -> [TestIdentifier]
}

struct TestCaseListService: TestCaseListServicing {
    private let listTestCasesService: ListTestCasesServicing

    init(
        listTestCasesService: ListTestCasesServicing = ListTestCasesService()
    ) {
        self.listTestCasesService = listTestCasesService
    }

    func listAllTestCases(
        fullHandle: String,
        serverURL: URL,
        state: Operations.listTestCases.Input.Query.statePayload
    ) async throws -> [TestIdentifier] {
        var allIdentifiers: [TestIdentifier] = []
        var page = 1
        while true {
            let response = try await listTestCasesService.listTestCases(
                fullHandle: fullHandle,
                serverURL: serverURL,
                flaky: nil,
                quarantined: nil,
                state: state,
                page: page,
                pageSize: 500
            )
            let identifiers = try response.test_cases.map { testCase in
                try TestIdentifier(
                    target: testCase.module.name,
                    class: testCase.suite?.name,
                    method: testCase.name
                )
            }
            allIdentifiers.append(contentsOf: identifiers)
            if !response.pagination_metadata.has_next_page {
                break
            }
            page += 1
        }
        return allIdentifiers
    }
}
