import Foundation
import Path
import XCResultKit

public struct InvocationRecord {
    public struct ActionRecord {
        public let actionResult: Result
        public let startedTime: Date
        public let endedTime: Date
        public let testPlanName: String?

        public init(actionResult: Result, startedTime: Date, endedTime: Date, testPlanName: String?) {
            self.actionResult = actionResult
            self.startedTime = startedTime
            self.endedTime = endedTime
            self.testPlanName = testPlanName
        }

        init(result: XCResultKit.ActionRecord) {
            actionResult = Result(result: result.actionResult)
            startedTime = result.startedTime
            endedTime = result.endedTime
            testPlanName = result.testPlanName
        }
    }

    public struct Result {
        public let testRefId: String?

        public init(testRefId: String?) {
            self.testRefId = testRefId
        }

        init(result: ActionResult) {
            testRefId = result.testsRef?.id
        }
    }

    public struct TestPlanRunSummaries {
        public let summaries: [TestPlanRunSummary]

        public init(summaries: [TestPlanRunSummary]) {
            self.summaries = summaries
        }

        init(
            resultFile: XCResultFile,
            testPlanRunSummaries: ActionTestPlanRunSummaries,
            rootDirectory: AbsolutePath?
        ) {
            summaries = testPlanRunSummaries.summaries.map {
                TestPlanRunSummary(
                    resultFile: resultFile,
                    testPlanRunSummary: $0,
                    rootDirectory: rootDirectory
                )
            }
        }
    }

    public struct TestPlanRunSummary {
        public let testableSummaries: [TestableSummary]

        public init(testableSummaries: [TestableSummary]) {
            self.testableSummaries = testableSummaries
        }

        init(
            resultFile: XCResultFile,
            testPlanRunSummary: ActionTestPlanRunSummary,
            rootDirectory: AbsolutePath?
        ) {
            testableSummaries = testPlanRunSummary.testableSummaries.map {
                TestableSummary(
                    resultFile: resultFile,
                    testableSummary: $0,
                    rootDirectory: rootDirectory
                )
            }
        }
    }

    public struct TestableSummary {
        public let targetName: String?
        public let tests: [TestSummaryGroup]

        public init(targetName: String, tests: [TestSummaryGroup]) {
            self.targetName = targetName
            self.tests = tests
        }

        init(resultFile: XCResultFile, testableSummary: ActionTestableSummary, rootDirectory: AbsolutePath?) {
            targetName = testableSummary.targetName
            let globalTests = testableSummary.globalTests.map { TestMetadata(
                resultFile: resultFile,
                testMetadata: $0,
                rootDirectory: rootDirectory
            ) }
            tests = testableSummary.tests.map {
                TestSummaryGroup(
                    resultFile: resultFile,
                    testSummaryGroup: $0,
                    rootDirectory: rootDirectory
                )
            } + [
                TestSummaryGroup(subtests: globalTests, subtestGroups: []),
            ]
        }
    }

    public struct TestSummaryGroup {
        public let subtests: [TestMetadata]
        public let subtestGroups: [TestSummaryGroup]

        public init(subtests: [TestMetadata], subtestGroups: [TestSummaryGroup]) {
            self.subtests = subtests
            self.subtestGroups = subtestGroups
        }

        init(
            resultFile: XCResultFile,
            testSummaryGroup: ActionTestSummaryGroup,
            rootDirectory: AbsolutePath?
        ) {
            subtests = testSummaryGroup.subtests.map {
                TestMetadata(
                    resultFile: resultFile,
                    testMetadata: $0,
                    rootDirectory: rootDirectory
                )
            }
            subtestGroups = testSummaryGroup.subtestGroups.map {
                TestSummaryGroup(
                    resultFile: resultFile,
                    testSummaryGroup: $0,
                    rootDirectory: rootDirectory
                )
            }
        }
    }

    public struct TestMetadata {
        public let name: String?
        public let suiteName: String?
        public let testStatus: String
        public let duration: Int?
        public let failures: [TestCaseFailure]

        public init(
            name: String?,
            suiteName: String?,
            testStatus: String,
            duration: Int?,
            failures: [TestCaseFailure]
        ) {
            self.name = name
            self.suiteName = suiteName
            self.testStatus = testStatus
            self.duration = duration
            self.failures = failures
        }

        init(resultFile: XCResultFile, testMetadata: ActionTestMetadata, rootDirectory: AbsolutePath?) {
            name = testMetadata.name
            if let identifier = testMetadata.identifier {
                suiteName = Self.suiteName(from: identifier)
            } else {
                suiteName = nil
            }
            testStatus = testMetadata.testStatus
            duration = testMetadata.duration.map { Int($0 * 1000) }
            if let summaryRef = testMetadata.summaryRef,
               let summary = resultFile.getActionTestSummary(id: summaryRef.id)
            {
                failures = summary.failureSummaries.map {
                    TestCaseFailure($0, rootDirectory: rootDirectory)
                }
            } else {
                failures = []
            }
        }

        private static func suiteName(from testIdentifier: String) -> String? {
            let components = testIdentifier.split(separator: "/")

            if components.count == 2 {
                return String(components[0])
            } else {
                return nil
            }
        }
    }

    public let actions: [ActionRecord]
    public let testSummaries: [TestPlanRunSummaries]
    public let path: URL

    public init(actions: [ActionRecord], testSummaries: [TestPlanRunSummaries], path: URL) {
        self.actions = actions
        self.testSummaries = testSummaries
        self.path = path
    }

    init(resultFile: XCResultFile, invocationRecord: ActionsInvocationRecord, rootDirectory: AbsolutePath?) {
        actions = invocationRecord.actions.map { .init(result: $0) }
        testSummaries = actions
            .compactMap(\.actionResult.testRefId)
            .compactMap { resultFile.getTestPlanRunSummaries(id: $0) }
            .map {
                TestPlanRunSummaries(
                    resultFile: resultFile,
                    testPlanRunSummaries: $0,
                    rootDirectory: rootDirectory
                )
            }
        path = resultFile.url
    }
}

extension InvocationRecord.TestSummaryGroup {
    var hasFailedTests: Bool {
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
    var isFailed: Bool {
        return isSuccessful == false && isSkipped == false
    }

    var isSuccessful: Bool {
        return testStatus == "Success" || testStatus == "Expected Failure"
    }

    private var isSkipped: Bool {
        return testStatus == "Skipped"
    }
}
