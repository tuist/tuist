//
//  XCResultParser.swift
//  Tuist
//
//  Created by Simon Cook on 27/02/2025.
//

import Foundation
import XCResultKit

final class XCResultParser {
    private let resultFile: XCResultFile
    private let invocationRecord: ActionsInvocationRecord
    
    init?(url: URL) {
        let resultFile = XCResultFile(url: url)
        guard let invocationRecord = resultFile.getInvocationRecord() else { return nil }
        self.resultFile = resultFile
        self.invocationRecord = invocationRecord
    }
    
    func successfulTestTargets() -> Set<String> {
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

private extension ActionTestSummaryGroup {
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

private extension ActionTestMetadata {
    var isFailed: Bool {
        return isSuccessful == false && isSkipped == false
    }

    var isSuccessful: Bool {
        return testStatus == "Success" || testStatus == "Expected Failure"
    }

    var isSkipped: Bool {
        return testStatus == "Skipped"
    }
}
