import Mockable
import TuistAlert
import TuistConfig
import TuistCore
import TuistLogging
import TuistServer
import TuistXCResultService

struct QuarantineClassificationResult {
    let quarantinedFailures: [TestCase]
    let realFailures: [TestCase]

    var onlyQuarantinedFailures: Bool {
        !quarantinedFailures.isEmpty && realFailures.isEmpty
    }
}

@Mockable
protocol TestQuarantineServicing {
    func quarantinedTests(
        config: Tuist,
        skipQuarantine: Bool
    ) async -> [TestIdentifier]

    func handleQuarantinedFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
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

    func handleQuarantinedFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> Bool {
        guard !quarantinedTests.isEmpty else { return false }

        let failedTestCases = testSummary.testCases.filter { $0.status == .failed }
        var quarantinedFailures: [TestCase] = []
        var realFailures: [TestCase] = []

        for testCase in failedTestCases {
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
                quarantinedFailures.append(testCase)
            } else {
                realFailures.append(testCase)
            }
        }

        if quarantinedFailures.isEmpty {
            return false
        }

        if realFailures.isEmpty {
            let failureNames = quarantinedFailures.map { testCase in
                [testCase.module, testCase.testSuite, testCase.name]
                    .compactMap { $0 }
                    .joined(separator: "/")
            }.joined(separator: ", ")
            Logger.current.notice(
                "\(quarantinedFailures.count) quarantined test(s) failed (exit code overridden to 0): \(failureNames)",
                metadata: .subsection
            )
            return true
        }

        Logger.current.notice(
            "\(quarantinedFailures.count) quarantined test(s) failed, \(realFailures.count) non-quarantined test(s) failed",
            metadata: .subsection
        )
        return false
    }
}
