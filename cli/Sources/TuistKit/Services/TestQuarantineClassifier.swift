import Mockable
import TuistCore
import TuistLogging
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
    func classifyFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> QuarantineClassificationResult

    /// Classifies failures and logs the result.
    /// Returns `true` if only quarantined tests failed (exit code should be overridden to 0).
    func handleQuarantinedFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> Bool
}

struct TestQuarantineService: TestQuarantineServicing {
    func classifyFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> QuarantineClassificationResult {
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

        return QuarantineClassificationResult(quarantinedFailures: quarantinedFailures, realFailures: realFailures)
    }

    func handleQuarantinedFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> Bool {
        guard !quarantinedTests.isEmpty else { return false }

        let result = classifyFailures(testSummary: testSummary, quarantinedTests: quarantinedTests)

        if result.onlyQuarantinedFailures {
            let failureNames = result.quarantinedFailures.map { testCase in
                [testCase.module, testCase.testSuite, testCase.name]
                    .compactMap { $0 }
                    .joined(separator: "/")
            }.joined(separator: ", ")
            Logger.current.notice(
                "\(result.quarantinedFailures.count) quarantined test(s) failed (exit code overridden to 0): \(failureNames)",
                metadata: .subsection
            )
            return true
        } else if !result.realFailures.isEmpty, !result.quarantinedFailures.isEmpty {
            Logger.current.notice(
                "\(result.quarantinedFailures.count) quarantined test(s) failed, \(result.realFailures.count) non-quarantined test(s) failed",
                metadata: .subsection
            )
        }

        return false
    }
}
