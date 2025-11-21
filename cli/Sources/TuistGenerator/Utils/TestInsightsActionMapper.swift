import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
protocol TestInsightsActionMapping {
    func map(
        _ testAction: TestAction?,
        target: TargetReference?,
        testInsightsDisabled: Bool
    ) async throws -> TestAction?
}

struct TestInsightsActionMapper: TestInsightsActionMapping {
    func map(
        _ testAction: TestAction?,
        target: TargetReference?,
        testInsightsDisabled: Bool
    ) async throws -> TestAction? {
        guard var testAction,
              !testInsightsDisabled,
              let currentExecutablePath = Environment.current.currentExecutablePath() else { return testAction }

        testAction.postActions.append(
            ExecutionAction(
                title: "Push test insights",
                scriptText: "\(currentExecutablePath.pathString) inspect test",
                target: target,
                shellPath: nil
            )
        )
        return testAction
    }
}
