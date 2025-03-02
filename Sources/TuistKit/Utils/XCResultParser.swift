import Foundation
import Mockable
import Path
import XCResultKit

@Mockable
public protocol XCResultParsing {
    func parse(path: AbsolutePath) -> ParsedXCResult?
}

public struct ParsedXCResult {
    let passingTestTargetNames: Set<String>
}

struct XCResultParser: XCResultParsing {
    func parse(path: AbsolutePath) -> ParsedXCResult? {
        let resultFile = XCResultFile(url: path.url)
        guard let invocationRecord = resultFile.getInvocationRecord() else { return nil }

        return ParsedXCResult(
            passingTestTargetNames: successfulTestTargets(resultFile: resultFile, invocationRecord: invocationRecord)
        )
    }

    private func successfulTestTargets(resultFile: XCResultFile, invocationRecord: ActionsInvocationRecord) -> Set<String> {
        let testRefs = invocationRecord.actions.compactMap { $0.actionResult.testsRef?.id }
        var passingTargets = [String]()

        for testRefId in testRefs {
            guard let testSummary = resultFile.getTestPlanRunSummaries(id: testRefId) else { continue }

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

extension ActionTestSummaryGroup {
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

extension ActionTestMetadata {
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
