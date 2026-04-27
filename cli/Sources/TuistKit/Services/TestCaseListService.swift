import Mockable
import TuistAlert
import TuistConfig
import TuistCore
import TuistServer
import TuistXCResultService
import XCResultParser

@Mockable
protocol TestCaseListServicing {
    /// Fetch all test cases for `config.fullHandle` matching the given state
    /// (e.g. `.muted` / `.skipped`) and return them as `TestIdentifier`s.
    ///
    /// Returns an empty array when:
    /// - `skipQuarantine` is `true`,
    /// - `config.fullHandle` is `nil`, or
    /// - the request fails (a warning is surfaced via `AlertController`).
    func listTestCases(
        config: Tuist,
        state: Operations.listTestCases.Input.Query.statePayload,
        skipQuarantine: Bool
    ) async -> [TestIdentifier]
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
        state: Operations.listTestCases.Input.Query.statePayload,
        skipQuarantine: Bool
    ) async -> [TestIdentifier] {
        guard !skipQuarantine, let fullHandle = config.fullHandle else {
            return []
        }
        do {
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
        } catch {
            AlertController.current.warning(
                .alert("Failed to fetch \(state.rawValue) test cases: \(error.localizedDescription). Running all tests.")
            )
            return []
        }
    }
}
