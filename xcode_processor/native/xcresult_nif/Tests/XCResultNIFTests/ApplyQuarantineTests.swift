import Foundation
import Path
import Testing
import XCResultParser
@testable import XCResultNIF

struct ApplyQuarantineTests {
    @Test
    func demotesRunStatusToPassedWhenAllFailingCasesAreQuarantined() throws {
        let xcresult = try makeFakeXCResult(quarantined: [
            QuarantineFixture(target: "AppTests", class: "FlakySuite", method: "testFlaky"),
        ])
        defer { try? FileManager.default.removeItem(atPath: xcresult.parentDirectory.pathString) }

        let summary = makeSummary(
            status: .failed,
            cases: [
                makeCase(name: "testStable", suite: "FlakySuite", module: "AppTests", status: .passed),
                makeCase(name: "testFlaky", suite: "FlakySuite", module: "AppTests", status: .failed),
            ]
        )

        let result = applyQuarantine(to: summary, at: xcresult)

        #expect(result.status == .passed)
        let cases = result.testModules.flatMap(\.testCases)
        #expect(cases.first { $0.name == "testFlaky" }?.isQuarantined == true)
        #expect(cases.first { $0.name == "testStable" }?.isQuarantined == false)
        #expect(cases.first { $0.name == "testFlaky" }?.status == .failed)
    }

    @Test
    func keepsRunStatusFailedWhenAtLeastOneFailingCaseIsNotQuarantined() throws {
        let xcresult = try makeFakeXCResult(quarantined: [
            QuarantineFixture(target: "AppTests", class: "Suite", method: "testFlaky"),
        ])
        defer { try? FileManager.default.removeItem(atPath: xcresult.parentDirectory.pathString) }

        let summary = makeSummary(
            status: .failed,
            cases: [
                makeCase(name: "testFlaky", suite: "Suite", module: "AppTests", status: .failed),
                makeCase(name: "testReal", suite: "Suite", module: "AppTests", status: .failed),
            ]
        )

        let result = applyQuarantine(to: summary, at: xcresult)

        #expect(result.status == .failed)
    }

    @Test
    func leavesSummaryUnchangedWhenQuarantinedTestsJsonIsAbsent() throws {
        let xcresult = try makeFakeXCResult(quarantined: nil)
        defer { try? FileManager.default.removeItem(atPath: xcresult.parentDirectory.pathString) }

        let summary = makeSummary(
            status: .failed,
            cases: [makeCase(name: "testA", suite: "Suite", module: "AppTests", status: .failed)]
        )

        let result = applyQuarantine(to: summary, at: xcresult)

        #expect(result.status == .failed)
        #expect(result.testModules.flatMap(\.testCases).allSatisfy { !$0.isQuarantined })
    }

    private struct QuarantineFixture: Encodable {
        let target: String
        let `class`: String?
        let method: String?
    }

    private func makeFakeXCResult(quarantined: [QuarantineFixture]?) throws -> AbsolutePath {
        let parent = NSTemporaryDirectory() + "xcresult_nif_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let bundle = parent + "/Test.xcresult"
        try FileManager.default.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        if let quarantined {
            let url = URL(fileURLWithPath: bundle + "/quarantined_tests.json")
            try JSONEncoder().encode(quarantined).write(to: url)
        }
        return try AbsolutePath(validating: bundle)
    }

    private func makeSummary(status: TestStatus, cases: [TestCase]) -> TestSummary {
        TestSummary(
            testPlanName: "Plan",
            status: status,
            duration: 0,
            testModules: [
                TestModule(name: "AppTests", status: status, duration: 0, testSuites: [], testCases: cases),
            ]
        )
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
