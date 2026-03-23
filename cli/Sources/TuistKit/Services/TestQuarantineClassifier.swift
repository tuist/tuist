import Mockable
import TuistAlert
import TuistConfig
import TuistCore
import TuistLogging
import TuistServer
import TuistXCResultService

@Mockable
protocol TestQuarantineServicing {
    func quarantinedTests(
        config: Tuist,
        skipQuarantine: Bool
    ) async -> [TestIdentifier]

    func markQuarantinedTests(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> TestSummary

    func onlyQuarantinedTestsFailed(
        testSummary: TestSummary
    ) -> Bool
}

struct TestQuarantineService: TestQuarantineServicing {
    private let listTestCasesService: ListTestCasesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        listTestCasesService: ListTestCasesServicing = ListTestCasesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.listTestCasesService = listTestCasesService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func quarantinedTests(
        config: Tuist,
        skipQuarantine: Bool = false
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
                quarantined: true,
                page: 1,
                pageSize: 500
            )
            let tests = try response.test_cases.map { testCase in
                try TestIdentifier(
                    target: testCase.module.name,
                    class: testCase.suite?.name,
                    method: testCase.name
                )
            }
            if !tests.isEmpty {
                Logger.current.notice(
                    "Found \(tests.count) quarantined test(s)",
                    metadata: .subsection
                )
            }
            return tests
        } catch {
            AlertController.current.warning(
                .alert("Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests.")
            )
            return []
        }
    }

    func markQuarantinedTests(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> TestSummary {
        guard !quarantinedTests.isEmpty else { return testSummary }
        var result = testSummary
        for moduleIndex in result.testModules.indices {
            for caseIndex in result.testModules[moduleIndex].testCases.indices {
                let testCase = result.testModules[moduleIndex].testCases[caseIndex]
                let isQuarantined = quarantinedTests.contains { quarantined in
                    guard testCase.module == quarantined.target else { return false }
                    if let quarantinedClass = quarantined.class,
                       testCase.testSuite != quarantinedClass
                    {
                        return false
                    }
                    if let quarantinedMethod = quarantined.method,
                       testCase.name != quarantinedMethod
                    {
                        return false
                    }
                    return true
                }
                if isQuarantined {
                    result.testModules[moduleIndex].testCases[caseIndex].isQuarantined = true
                }
            }
        }
        return result
    }

    func onlyQuarantinedTestsFailed(
        testSummary: TestSummary
    ) -> Bool {
        let failedTests = testSummary.testCases.filter { $0.status == .failed }
        guard !failedTests.isEmpty else { return false }
        return failedTests.allSatisfy(\.isQuarantined)
    }
}
