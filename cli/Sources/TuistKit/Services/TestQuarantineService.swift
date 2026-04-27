import Mockable
import TuistCore
import TuistXCResultService
import XCResultParser

@Mockable
protocol TestQuarantineServicing {
    func markQuarantinedTests(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> TestSummary

    func onlyQuarantinedTestsFailed(
        testSummary: TestSummary
    ) -> Bool

    func onlyQuarantinedTestsFailed(
        testStatuses: TestResultStatuses,
        quarantinedTests: [TestIdentifier]
    ) -> Bool
}

struct TestQuarantineService: TestQuarantineServicing {
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

    func onlyQuarantinedTestsFailed(
        testStatuses: TestResultStatuses,
        quarantinedTests: [TestIdentifier]
    ) -> Bool {
        guard !quarantinedTests.isEmpty else { return false }
        let failedTests = testStatuses.testCases.filter { $0.status == .failed }
        guard !failedTests.isEmpty else { return false }
        return failedTests.allSatisfy { testCase in
            quarantinedTests.contains { matches(testCaseStatus: testCase, quarantined: $0) }
        }
    }

    private func matches(testCaseStatus: TestResultStatuses.TestCaseStatus, quarantined: TestIdentifier) -> Bool {
        guard testCaseStatus.module == quarantined.target else { return false }
        if let quarantinedClass = quarantined.class, testCaseStatus.testSuite != quarantinedClass {
            return false
        }
        if let quarantinedMethod = quarantined.method, testCaseStatus.name != quarantinedMethod {
            return false
        }
        return true
    }
}
