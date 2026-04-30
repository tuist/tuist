import Foundation

extension TestSummary {
    /// Returns a copy of the summary with `isQuarantined` set on every test
    /// case that matches one of `quarantinedTests`, and with run, module, and
    /// suite statuses demoted from `.failed` to `.passed` when the only
    /// failing cases are quarantined.
    ///
    /// Quarantined (muted) tests still run and still report a failure status
    /// at the test-case level — flakiness signal must not be lost — but they
    /// must not flip the higher-level rollups, because CI does not fail on
    /// them. Both the local CLI upload path and the server-side xcresult
    /// processor go through this single helper so the dashboard agrees with
    /// the CI exit code regardless of who computed the payload.
    public func applyingQuarantine(_ quarantinedTests: [QuarantinedTestIdentifier]) -> TestSummary {
        let updatedModules = testModules.map { $0.applyingQuarantine(quarantinedTests) }

        return TestSummary(
            testPlanName: testPlanName,
            status: TestSummary.demotedStatus(status, for: updatedModules.flatMap(\.testCases)),
            duration: duration,
            testModules: updatedModules,
            runDestinations: runDestinations
        )
    }

    static func demotedStatus(_ status: TestStatus, for testCases: [TestCase]) -> TestStatus {
        guard status == .failed else { return status }
        let failures = testCases.filter { $0.status == .failed }
        guard !failures.isEmpty else { return .failed }
        return failures.allSatisfy(\.isQuarantined) ? .passed : .failed
    }
}

extension TestModule {
    func applyingQuarantine(_ quarantinedTests: [QuarantinedTestIdentifier]) -> TestModule {
        let updatedCases = testCases.map { testCase -> TestCase in
            var updated = testCase
            updated.isQuarantined = quarantinedTests.contains { $0.matches(testCase: testCase) }
            return updated
        }
        let updatedSuites = testSuites.map { suite in
            let suiteCases = updatedCases.filter { $0.testSuite == suite.name }
            return TestSuite(
                name: suite.name,
                status: TestSummary.demotedStatus(suite.status, for: suiteCases),
                duration: suite.duration
            )
        }

        return TestModule(
            name: name,
            status: TestSummary.demotedStatus(status, for: updatedCases),
            duration: duration,
            testSuites: updatedSuites,
            testCases: updatedCases
        )
    }
}
