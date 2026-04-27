import Mockable
import TuistAlert
import TuistConfig
import TuistCore
import TuistLogging
import TuistServer
import TuistXCResultService
import XCResultParser

public struct QuarantinedTests: Sendable, Hashable {
    public var muted: [TestIdentifier]
    public var skipped: [TestIdentifier]

    public init(muted: [TestIdentifier] = [], skipped: [TestIdentifier] = []) {
        self.muted = muted
        self.skipped = skipped
    }

    public static let empty = QuarantinedTests()

    public var all: [TestIdentifier] {
        muted + skipped
    }

    public var isEmpty: Bool {
        muted.isEmpty && skipped.isEmpty
    }
}

@Mockable
protocol TestQuarantineServicing {
    func quarantinedTests(
        config: Tuist,
        skipQuarantine: Bool
    ) async -> QuarantinedTests

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
    ) async -> QuarantinedTests {
        guard !skipQuarantine, let fullHandle = config.fullHandle else {
            return .empty
        }
        do {
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            // Two filtered calls (one per state) instead of one `quarantined=true`
            // call + client-side partition: keeps the wire format aligned with
            // how the dashboard reasons about modes, and means each request
            // only ships the rows for the mode we're about to act on.
            async let mutedPage = listTestCasesService.listTestCases(
                fullHandle: fullHandle,
                serverURL: serverURL,
                flaky: nil,
                quarantined: nil,
                state: .muted,
                page: 1,
                pageSize: 500
            )
            async let skippedPage = listTestCasesService.listTestCases(
                fullHandle: fullHandle,
                serverURL: serverURL,
                flaky: nil,
                quarantined: nil,
                state: .skipped,
                page: 1,
                pageSize: 500
            )
            let (mutedResponse, skippedResponse) = try await (mutedPage, skippedPage)
            let muted = try mutedResponse.test_cases.map(toIdentifier)
            let skipped = try skippedResponse.test_cases.map(toIdentifier)
            let total = muted.count + skipped.count
            if total > 0 {
                Logger.current.notice(
                    "Found \(total) quarantined test(s): \(muted.count) muted, \(skipped.count) skipped",
                    metadata: .subsection
                )
            }
            return QuarantinedTests(muted: muted, skipped: skipped)
        } catch {
            AlertController.current.warning(
                .alert("Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests.")
            )
            return .empty
        }
    }

    private func toIdentifier(
        _ testCase: Components.Schemas.TestCase
    ) throws -> TestIdentifier {
        try TestIdentifier(
            target: testCase.module.name,
            class: testCase.suite?.name,
            method: testCase.name
        )
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
