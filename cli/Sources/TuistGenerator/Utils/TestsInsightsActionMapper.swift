import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
protocol TestsInsightsActionMapping {
    /// Maps a build action to track build insights.
    func map(
        _ testAction: TestAction,
        testsInsightsDisabled: Bool
    ) async throws -> TestAction
}

struct TestsInsightsActionMapper: TestsInsightsActionMapping {
    func map(
        _ testAction: TestAction,
        testsInsightsDisabled: Bool
    ) async throws -> TestAction {
        guard !testsInsightsDisabled,
              let currentExecutablePath = Environment.current.currentExecutablePath() else { return testAction }

        var testAction = testAction
        testAction.postActions.append(
            ExecutionAction(
                title: "Push tests insights",
                scriptText: "\(currentExecutablePath.pathString) inspect tests",
                target: nil,
                shellPath: nil
            )
        )
        return testAction
    }
}
