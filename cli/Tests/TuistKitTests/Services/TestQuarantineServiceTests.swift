import Foundation
import Mockable
import Testing
import TuistAlert
import TuistConfig
import TuistCore
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCResultService
import XCResultParser

@testable import TuistKit

@Suite
struct TestQuarantineServiceTests {
    private let subject = TestQuarantineService()

    // MARK: - markQuarantinedTests

    @Test
    func markQuarantinedTests_returnsUnchanged_whenQuarantineListIsEmpty() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .passed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .passed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .passed,
                        failures: []
                    ),
                ]),
            ]
        )

        let result = subject.markQuarantinedTests(testSummary: summary, quarantinedTests: [])

        #expect(result.testCases.filter(\.isQuarantined).isEmpty)
    }

    @Test
    func markQuarantinedTests_marksByTargetClassMethod() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                    TestCase(
                        name: "testB()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .passed,
                        failures: []
                    ),
                ]),
            ]
        )

        let quarantined = [try TestIdentifier(target: "AppTests", class: "Suite", method: "testA()")]
        let result = subject.markQuarantinedTests(testSummary: summary, quarantinedTests: quarantined)

        #expect(result.testCases[0].isQuarantined == true)
        #expect(result.testCases[1].isQuarantined == false)
    }

    @Test
    func markQuarantinedTests_matchesByTargetOnly() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                    TestCase(
                        name: "testB()",
                        testSuite: "Other",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                ]),
            ]
        )

        let quarantined = [try TestIdentifier(target: "AppTests")]
        let result = subject.markQuarantinedTests(testSummary: summary, quarantinedTests: quarantined)

        #expect(result.testCases.filter { !$0.isQuarantined }.isEmpty)
    }

    @Test
    func markQuarantinedTests_doesNotMatchDifferentTarget() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                ]),
            ]
        )

        let quarantined = [try TestIdentifier(target: "CoreTests", class: "Suite", method: "testA()")]
        let result = subject.markQuarantinedTests(testSummary: summary, quarantinedTests: quarantined)

        #expect(result.testCases.filter(\.isQuarantined).isEmpty)
    }

    @Test
    func markQuarantinedTests_marksAcrossModules() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 200,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                ]),
                TestModule(name: "CoreTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(name: "testB()", testSuite: nil, module: "CoreTests", duration: 50, status: .failed, failures: []),
                ]),
            ]
        )

        let quarantined = [
            try TestIdentifier(target: "AppTests", class: "Suite", method: "testA()"),
            try TestIdentifier(target: "CoreTests", class: nil, method: "testB()"),
        ]
        let result = subject.markQuarantinedTests(testSummary: summary, quarantinedTests: quarantined)

        #expect(result.testModules[0].testCases[0].isQuarantined == true)
        #expect(result.testModules[1].testCases[0].isQuarantined == true)
    }

    // MARK: - onlyQuarantinedTestsFailed

    @Test
    func onlyQuarantinedTestsFailed_returnsFalse_whenNoFailures() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .passed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .passed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .passed,
                        failures: []
                    ),
                ]),
            ]
        )

        #expect(subject.onlyQuarantinedTestsFailed(testSummary: summary) == false)
    }

    @Test
    func onlyQuarantinedTestsFailed_returnsTrue_whenAllFailuresAreQuarantined() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()", testSuite: "Suite", module: "AppTests", duration: 50,
                        status: .failed, failures: [], isQuarantined: true
                    ),
                    TestCase(
                        name: "testB()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .passed,
                        failures: []
                    ),
                ]),
            ]
        )

        #expect(subject.onlyQuarantinedTestsFailed(testSummary: summary) == true)
    }

    @Test
    func onlyQuarantinedTestsFailed_returnsFalse_whenMixedFailures() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()", testSuite: "Suite", module: "AppTests", duration: 50,
                        status: .failed, failures: [], isQuarantined: true
                    ),
                    TestCase(
                        name: "testB()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                ]),
            ]
        )

        #expect(subject.onlyQuarantinedTestsFailed(testSummary: summary) == false)
    }

    @Test
    func onlyQuarantinedTestsFailed_returnsFalse_whenNonQuarantinedFailure() throws {
        let summary = TestSummary(
            testPlanName: nil, status: .failed, duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .failed, duration: 100, testSuites: [], testCases: [
                    TestCase(
                        name: "testA()",
                        testSuite: "Suite",
                        module: "AppTests",
                        duration: 50,
                        status: .failed,
                        failures: []
                    ),
                ]),
            ]
        )

        #expect(subject.onlyQuarantinedTestsFailed(testSummary: summary) == false)
    }

    // MARK: - onlyQuarantinedTestsFailed (TestResultStatuses)

    @Test
    func onlyQuarantinedTestsFailed_statuses_returnsFalse_whenNoQuarantinedTests() throws {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: "Suite", module: "AppTests", status: .failed),
        ])
        #expect(subject.onlyQuarantinedTestsFailed(testStatuses: statuses, quarantinedTests: []) == false)
    }

    @Test
    func onlyQuarantinedTestsFailed_statuses_returnsFalse_whenNoFailures() throws {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: "Suite", module: "AppTests", status: .passed),
        ])
        let quarantined = [try TestIdentifier(target: "AppTests", class: "Suite", method: "testA()")]
        #expect(subject.onlyQuarantinedTestsFailed(testStatuses: statuses, quarantinedTests: quarantined) == false)
    }

    @Test
    func onlyQuarantinedTestsFailed_statuses_returnsTrue_whenAllFailuresQuarantined() throws {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: "Suite", module: "AppTests", status: .failed),
            .init(name: "testB()", testSuite: "Suite", module: "AppTests", status: .passed),
        ])
        let quarantined = [try TestIdentifier(target: "AppTests", class: "Suite", method: "testA()")]
        #expect(subject.onlyQuarantinedTestsFailed(testStatuses: statuses, quarantinedTests: quarantined) == true)
    }

    @Test
    func onlyQuarantinedTestsFailed_statuses_returnsFalse_whenNonQuarantinedTestFailed() throws {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: "Suite", module: "AppTests", status: .failed),
            .init(name: "testB()", testSuite: "Suite", module: "AppTests", status: .failed),
        ])
        let quarantined = [try TestIdentifier(target: "AppTests", class: "Suite", method: "testA()")]
        #expect(subject.onlyQuarantinedTestsFailed(testStatuses: statuses, quarantinedTests: quarantined) == false)
    }

    @Test
    func onlyQuarantinedTestsFailed_statuses_matchesByTargetOnly() throws {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: "Suite", module: "AppTests", status: .failed),
            .init(name: "testB()", testSuite: "Other", module: "AppTests", status: .failed),
        ])
        let quarantined = [try TestIdentifier(target: "AppTests")]
        #expect(subject.onlyQuarantinedTestsFailed(testStatuses: statuses, quarantinedTests: quarantined) == true)
    }
}

extension Components.Schemas.TestCase {
    fileprivate static func test(
        id: String = "1",
        isQuarantined: Bool = true,
        module: Components.Schemas.TestCase.modulePayload = .test(),
        name: String = "testExample()",
        state: String = "muted",
        suite: Components.Schemas.TestCase.suitePayload? = nil
    ) -> Self {
        .init(
            avg_duration: 100,
            id: id,
            is_flaky: false,
            is_quarantined: isQuarantined,
            module: module,
            name: name,
            state: state,
            suite: suite,
            url: "https://tuist.dev/test-cases/\(id)"
        )
    }
}

extension Components.Schemas.TestCase.modulePayload {
    fileprivate static func test(id: String = "1", name: String = "AppTests") -> Self {
        .init(id: id, name: name)
    }
}

extension Components.Schemas.TestCase.suitePayload {
    fileprivate static func test(id: String = "1", name: String = "TestSuite") -> Self {
        .init(id: id, name: name)
    }
}
