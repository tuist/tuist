import TuistCore
import XCResultParser

extension RunReportTestRun {
    /// Builds a lightweight per-scheme test report from xcresult statuses, used to render the
    /// GitHub Actions job summary locally.
    init(scheme: String, testStatuses: TestResultStatuses) {
        self.init(
            scheme: scheme,
            totalTests: testStatuses.testCases.count,
            skippedTests: testStatuses.testCases.filter { $0.status == .skipped }.count,
            failedTestNames: testStatuses.testCases
                .filter { $0.status == .failed }
                .map { "\($0.testSuite).\($0.name)" }
        )
    }
}
