import Foundation
import Testing
@testable import XCResultParser

struct TestSummaryQuarantineTests {
    @Test
    func appliesQuarantineFlagAndDemotesStatusWhenAllFailuresAreQuarantined() {
        let summary = makeSummary(
            status: .failed,
            modules: [
                makeModule(
                    name: "AppTests",
                    status: .failed,
                    suites: [makeSuite(name: "FlakySuite", status: .failed)],
                    cases: [
                        makeCase(name: "testStable", suite: "FlakySuite", module: "AppTests", status: .passed),
                        makeCase(name: "testFlaky", suite: "FlakySuite", module: "AppTests", status: .failed),
                    ]
                ),
            ]
        )

        let result = summary.applyingQuarantine([
            QuarantinedTestIdentifier(target: "AppTests", class: "FlakySuite", method: "testFlaky"),
        ])

        #expect(result.status == .passed)
        #expect(result.testModules[0].status == .passed)
        #expect(result.testModules[0].testSuites[0].status == .passed)

        let cases = result.testModules[0].testCases
        #expect(cases.first { $0.name == "testFlaky" }?.isQuarantined == true)
        #expect(cases.first { $0.name == "testStable" }?.isQuarantined == false)
    }

    @Test
    func keepsFailureStatusWhenAtLeastOneFailingTestIsNotQuarantined() {
        let summary = makeSummary(
            status: .failed,
            modules: [
                makeModule(
                    name: "AppTests",
                    status: .failed,
                    suites: [makeSuite(name: "Suite", status: .failed)],
                    cases: [
                        makeCase(name: "testFlaky", suite: "Suite", module: "AppTests", status: .failed),
                        makeCase(name: "testReal", suite: "Suite", module: "AppTests", status: .failed),
                    ]
                ),
            ]
        )

        let result = summary.applyingQuarantine([
            QuarantinedTestIdentifier(target: "AppTests", class: "Suite", method: "testFlaky"),
        ])

        #expect(result.status == .failed)
        #expect(result.testModules[0].status == .failed)
        #expect(result.testModules[0].testSuites[0].status == .failed)
    }

    @Test
    func leavesPassingRunsUntouched() {
        let summary = makeSummary(
            status: .passed,
            modules: [
                makeModule(
                    name: "AppTests",
                    status: .passed,
                    suites: [makeSuite(name: "Suite", status: .passed)],
                    cases: [makeCase(name: "testA", suite: "Suite", module: "AppTests", status: .passed)]
                ),
            ]
        )

        let result = summary.applyingQuarantine([
            QuarantinedTestIdentifier(target: "AppTests", class: "Suite", method: "testA"),
        ])

        #expect(result.status == .passed)
        #expect(result.testModules[0].testCases[0].isQuarantined == true)
    }

    @Test
    func quarantineByTargetOnlyMatchesAllCasesInThatTarget() {
        let summary = makeSummary(
            status: .failed,
            modules: [
                makeModule(
                    name: "AppTests",
                    status: .failed,
                    suites: [],
                    cases: [
                        makeCase(name: "testA", suite: nil, module: "AppTests", status: .failed),
                        makeCase(name: "testB", suite: nil, module: "AppTests", status: .failed),
                    ]
                ),
                makeModule(
                    name: "OtherTests",
                    status: .passed,
                    suites: [],
                    cases: [makeCase(name: "testC", suite: nil, module: "OtherTests", status: .passed)]
                ),
            ]
        )

        let result = summary.applyingQuarantine([QuarantinedTestIdentifier(target: "AppTests")])

        #expect(result.status == .passed)
        let firstModuleAllQuarantined = result.testModules[0].testCases.allSatisfy(\.isQuarantined)
        #expect(firstModuleAllQuarantined)
        #expect(result.testModules[1].testCases[0].isQuarantined == false)
    }

    private func makeSummary(status: TestStatus, modules: [TestModule]) -> TestSummary {
        TestSummary(
            testPlanName: "Plan",
            status: status,
            duration: 0,
            testModules: modules
        )
    }

    private func makeModule(
        name: String,
        status: TestStatus,
        suites: [TestSuite],
        cases: [TestCase]
    ) -> TestModule {
        TestModule(name: name, status: status, duration: 0, testSuites: suites, testCases: cases)
    }

    private func makeSuite(name: String, status: TestStatus) -> TestSuite {
        TestSuite(name: name, status: status, duration: 0)
    }

    private func makeCase(name: String, suite: String?, module: String, status: TestStatus) -> TestCase {
        TestCase(
            name: name,
            testSuite: suite,
            module: module,
            duration: 0,
            status: status,
            failures: []
        )
    }
}
