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
        return testSummary.applyingQuarantine(quarantinedTests.map(\.quarantineIdentifier))
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
        let identifiers = quarantinedTests.map(\.quarantineIdentifier)
        return failedTests.allSatisfy { testCase in
            identifiers.contains { $0.matches(testCaseStatus: testCase) }
        }
    }
}

extension TestIdentifier {
    fileprivate var quarantineIdentifier: QuarantinedTestIdentifier {
        QuarantinedTestIdentifier(target: target, class: `class`, method: method)
    }
}

extension QuarantinedTestIdentifier {
    fileprivate func matches(testCaseStatus: TestResultStatuses.TestCaseStatus) -> Bool {
        guard testCaseStatus.module == target else { return false }
        if let `class`, testCaseStatus.testSuite != `class` { return false }
        if let method, testCaseStatus.name != method { return false }
        return true
    }
}
