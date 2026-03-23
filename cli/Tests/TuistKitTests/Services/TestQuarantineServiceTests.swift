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

@testable import TuistKit

@Suite
struct TestQuarantineServiceTests {
    private let listTestCasesService = MockListTestCasesServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let subject: TestQuarantineService

    init() {
        subject = TestQuarantineService(
            listTestCasesService: listTestCasesService,
            serverEnvironmentService: serverEnvironmentService
        )
    }

    // MARK: - quarantinedTests

    @Test(.withMockedDependencies())
    func quarantinedTests_returnsEmpty_whenSkipQuarantineIsTrue() async throws {
        let config = Tuist.test(fullHandle: "org/project")
        let result = await subject.quarantinedTests(config: config, skipQuarantine: true)
        #expect(result.isEmpty)
    }

    @Test(.withMockedDependencies())
    func quarantinedTests_returnsEmpty_whenFullHandleIsNil() async throws {
        let config = Tuist.test(fullHandle: nil)
        let result = await subject.quarantinedTests(config: config, skipQuarantine: false)
        #expect(result.isEmpty)
    }

    @Test(.withMockedDependencies())
    func quarantinedTests_returnsEmpty_whenFetchFails() async throws {
        let config = Tuist.test(fullHandle: "org/project")
        let serverURL = URL(string: "https://tuist.dev")!

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        given(listTestCasesService)
            .listTestCases(
                fullHandle: .any, serverURL: .any, flaky: .any,
                quarantined: .any, page: .any, pageSize: .any
            )
            .willThrow(NSError(domain: "test", code: 500))

        let alertController = AlertController()
        let result = await AlertController.$current.withValue(alertController) {
            await subject.quarantinedTests(config: config, skipQuarantine: false)
        }

        #expect(result.isEmpty)
        let warnings = alertController.warnings()
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.plain().contains("Failed to fetch quarantined tests") == true)
    }

    @Test(.withMockedDependencies())
    func quarantinedTests_returnsTestIdentifiers() async throws {
        let config = Tuist.test(fullHandle: "org/project")
        let serverURL = URL(string: "https://tuist.dev")!

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(
            pagination_metadata: .init(
                current_page: 1, has_next_page: false, has_previous_page: false,
                page_size: 500, total_count: 2, total_pages: 1
            ),
            test_cases: [
                .test(id: "1", module: .test(name: "AppTests"), name: "testFoo()", suite: .test(name: "FooSuite")),
                .test(id: "2", module: .test(name: "CoreTests"), name: "testBar()"),
            ]
        )

        given(listTestCasesService)
            .listTestCases(
                fullHandle: .value("org/project"), serverURL: .value(serverURL), flaky: .value(nil),
                quarantined: .value(true), page: .value(1), pageSize: .value(500)
            )
            .willReturn(response)

        let result = await subject.quarantinedTests(config: config, skipQuarantine: false)

        let expected = [
            try TestIdentifier(target: "AppTests", class: "FooSuite", method: "testFoo()"),
            try TestIdentifier(target: "CoreTests", class: nil, method: "testBar()"),
        ]
        #expect(result == expected)
    }

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
}

private extension Components.Schemas.TestCase {
    static func test(
        id: String = "1",
        isQuarantined: Bool = true,
        module: Components.Schemas.TestCase.modulePayload = .test(),
        name: String = "testExample()",
        suite: Components.Schemas.TestCase.suitePayload? = nil
    ) -> Self {
        .init(
            avg_duration: 100,
            id: id,
            is_flaky: false,
            is_quarantined: isQuarantined,
            module: module,
            name: name,
            suite: suite,
            url: "https://tuist.dev/test-cases/\(id)"
        )
    }
}

private extension Components.Schemas.TestCase.modulePayload {
    static func test(id: String = "1", name: String = "AppTests") -> Self {
        .init(id: id, name: name)
    }
}

private extension Components.Schemas.TestCase.suitePayload {
    static func test(id: String = "1", name: String = "TestSuite") -> Self {
        .init(id: id, name: name)
    }
}
