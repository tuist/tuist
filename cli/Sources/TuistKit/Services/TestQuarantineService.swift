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
        result.testModules = result.testModules.map { module in
            var module = module
            module.testCases = module.testCases.map { testCase in
                var testCase = testCase
                testCase.isQuarantined = quarantinedTests.contains { matches(testCase: testCase, quarantined: $0) }
                return testCase
            }
            return module
        }
        if result.status == .failed, onlyQuarantinedTestsFailed(testSummary: result) {
            result.status = .passed
        }
        return result
    }

    private func matches(testCase: TestCase, quarantined: TestIdentifier) -> Bool {
        guard testCase.module == quarantined.target else { return false }
        if let quarantinedClass = quarantined.class, testCase.testSuite != quarantinedClass {
            return false
        }
        if let quarantinedMethod = quarantined.method, testCase.name != quarantinedMethod {
            return false
        }
        return true
    }

    func onlyQuarantinedTestsFailed(
        testSummary: TestSummary
    ) -> Bool {
        let failedTests = testSummary.testCases.filter { $0.status == .failed }
        guard !failedTests.isEmpty else { return false }
        return failedTests.allSatisfy(\.isQuarantined)
    }
}
