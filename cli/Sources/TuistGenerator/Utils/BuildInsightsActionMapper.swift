import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
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
        let warning = "warning: tuist inspect build failed, build insights were not uploaded"
        // A post-action that exits with a non-zero status fails the build.
        let scriptText = "\(currentExecutablePath.pathString) inspect build || echo \"\(warning)\""

        buildAction.postActions.append(
            ExecutionAction(
                title: "Push build insights",
                scriptText: scriptText,
                target: target,
                shellPath: nil
            )
        )
        buildAction.runPostActionsOnFailure = true
        return buildAction
    }
}
