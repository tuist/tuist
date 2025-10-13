import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
protocol BuildInsightsActionMapping {
    /// Maps a build action to track build insights.
    func map(
        _ buildAction: BuildAction,
        target: TargetReference?,
        buildInsightsDisabled: Bool
    ) async throws -> BuildAction
}

struct BuildInsightsActionMapper: BuildInsightsActionMapping {
    func map(
        _ buildAction: BuildAction,
        target: TargetReference?,
        buildInsightsDisabled: Bool
    ) async throws -> BuildAction {
        guard !buildInsightsDisabled,
              let currentExecutablePath = Environment.current.currentExecutablePath() else { return buildAction }

        var buildAction = buildAction
        buildAction.postActions.append(
            ExecutionAction(
                title: "Push build insights",
                scriptText: "\(currentExecutablePath.pathString) inspect build",
                target: target,
                shellPath: nil
            )
        )
        buildAction.runPostActionsOnFailure = true
        return buildAction
    }
}
