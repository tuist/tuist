import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
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

        let warning = "warning: tuist inspect test failed, test insights were not uploaded"
        // A post-action that exits with a non-zero status fails the build.
        let scriptText = "\(currentExecutablePath.pathString) inspect test || echo \"\(warning)\""

        testAction.postActions.append(
            ExecutionAction(
                title: "Push test insights",
                scriptText: scriptText,
                target: target,
                shellPath: nil
            )
        )
        return testAction
    }
}
