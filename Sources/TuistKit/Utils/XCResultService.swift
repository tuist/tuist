import Foundation
import Mockable
import Path
import XCResultKit

@Mockable
protocol XCResultServicing {
    func parse(path: AbsolutePath) -> InvocationRecord?
    func successfulTestTargets(invocationRecord: InvocationRecord) -> Set<String>
}

struct InvocationRecord {
    struct ActionRecord {
        let actionResult: Result

        init(actionResult: Result) {
            self.actionResult = actionResult
        }

        init(result: XCResultKit.ActionRecord) {
            actionResult = .init(result: result.actionResult)
        }
    }

    struct Result {
        let testRefId: String?

        init(testRefId: String?) {
            self.testRefId = testRefId
        }

        init(result: ActionResult) {
            testRefId = result.testsRef?.id
        }
    }

    struct TestPlanRunSummaries {
        let summaries: [TestPlanRunSummary]

        init(summaries: [TestPlanRunSummary]) {
            self.summaries = summaries
        }

        init(testPlanRunSummaries: ActionTestPlanRunSummaries) {
            summaries = testPlanRunSummaries.summaries.map { .init(testPlanRunSummary: $0) }
        }
    }

    struct TestPlanRunSummary {
        let testableSummaries: [TestableSummary]

        init(testableSummaries: [TestableSummary]) {
            self.testableSummaries = testableSummaries
        }

        init(testPlanRunSummary: ActionTestPlanRunSummary) {
            testableSummaries = testPlanRunSummary.testableSummaries.map { .init(testableSummary: $0) }
        }
    }

    struct TestableSummary {
        let targetName: String?
        let tests: [TestSummaryGroup]

        init(targetName: String, tests: [TestSummaryGroup]) {
            self.targetName = targetName
            self.tests = tests
        }

        init(testableSummary: ActionTestableSummary) {
            targetName = testableSummary.targetName
            tests = testableSummary.tests.map { .init(testSummaryGroup: $0) }
        }
    }

    struct TestSummaryGroup {
        let subtests: [TestMetadata]
        let subtestGroups: [TestSummaryGroup]

        init(subtests: [TestMetadata], subtestGroups: [TestSummaryGroup]) {
            self.subtests = subtests
            self.subtestGroups = subtestGroups
        }

        init(testSummaryGroup: ActionTestSummaryGroup) {
            subtests = testSummaryGroup.subtests.map { .init(testMetadata: $0) }
            subtestGroups = testSummaryGroup.subtestGroups.map { .init(testSummaryGroup: $0) }
        }
    }

    struct TestMetadata {
        let testStatus: String

        init(testStatus: String) {
            self.testStatus = testStatus
        }

        init(testMetadata: ActionTestMetadata) {
            testStatus = testMetadata.testStatus
        }
    }

    let actions: [ActionRecord]
    let testSummaries: [TestPlanRunSummaries]

    init(actions: [ActionRecord], testSummaries: [TestPlanRunSummaries]) {
        self.actions = actions
        self.testSummaries = testSummaries
    }

    init(resultFile: XCResultFile, invocationRecord: ActionsInvocationRecord) {
        actions = invocationRecord.actions.map { .init(result: $0) }
        testSummaries = actions
            .compactMap(\.actionResult.testRefId)
            .compactMap { resultFile.getTestPlanRunSummaries(id: $0) }
            .map { TestPlanRunSummaries(testPlanRunSummaries: $0) }
    }
}

struct XCResultService: XCResultServicing {
    func parse(path: AbsolutePath) -> InvocationRecord? {
        let resultFile = XCResultFile(url: path.url)
        guard let invocationRecord = resultFile.getInvocationRecord() else { return nil }

        return .init(resultFile: resultFile, invocationRecord: invocationRecord)
    }

    func successfulTestTargets(invocationRecord: InvocationRecord) -> Set<String> {
        var passingTargets = [String]()

        for testSummary in invocationRecord.testSummaries {
            for summary in testSummary.summaries {
                for testableSummary in summary.testableSummaries {
                    if testableSummary.tests.allSatisfy({ !$0.hasFailedTests }), let targetName = testableSummary.targetName {
                        passingTargets.append(targetName)
                    }
                }
            }
        }

        return Set(passingTargets)
    }
}

extension InvocationRecord.TestSummaryGroup {
    fileprivate var hasFailedTests: Bool {
        if subtests.first(where: \.isFailed) != nil {
            return true
        }
        if subtestGroups.first(where: \.hasFailedTests) != nil {
            return true
        }
        return false
    }
}

extension InvocationRecord.TestMetadata {
    fileprivate var isFailed: Bool {
        return isSuccessful == false && isSkipped == false
    }

    private var isSuccessful: Bool {
        return testStatus == "Success" || testStatus == "Expected Failure"
    }

    private var isSkipped: Bool {
        return testStatus == "Skipped"
    }
}
