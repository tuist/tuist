import Mockable
import TuistConfig
import TuistCore
import TuistServer

@Mockable
protocol TestCaseListServicing {
    /// Fetch all test cases for `config.fullHandle` matching the given state
    /// (e.g. `.muted` / `.skipped`) and return them as `TestIdentifier`s.
    ///
    /// Returns an empty array when `config.fullHandle` is `nil`. Otherwise
    /// throws on URL resolution, network, decoding, or `TestIdentifier`
    /// construction errors — call sites decide how to react (warn the user
    /// and fall back to running all tests, or surface the error directly).
    func listTestCases(
        config: Tuist,
        state: Operations.listTestCases.Input.Query.statePayload
    ) async throws -> [TestIdentifier]
}

struct TestCaseListService: TestCaseListServicing {
    private let listTestCasesService: ListTestCasesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        listTestCasesService: ListTestCasesServicing = ListTestCasesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.listTestCasesService = listTestCasesService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func listTestCases(
        config: Tuist,
        state: Operations.listTestCases.Input.Query.statePayload
    ) async throws -> [TestIdentifier] {
        guard let fullHandle = config.fullHandle else {
            return []
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let response = try await listTestCasesService.listTestCases(
            fullHandle: fullHandle,
            serverURL: serverURL,
            flaky: nil,
            quarantined: nil,
            state: state,
            page: 1,
            pageSize: 500
        )
        return try response.test_cases.map { testCase in
            try TestIdentifier(
                target: testCase.module.name,
                class: testCase.suite?.name,
                method: testCase.name
            )
        }
    }
}
