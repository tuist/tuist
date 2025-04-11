import FileSystem
import Foundation
import Mockable
import Path
import ServiceContextModule
import TuistSupport
import XcodeGraph

@Mockable
protocol BuildInsightsActionMapping {
    /// Maps a build action to track build insights.
    func map(
        _ buildAction: BuildAction,
        buildInsightsDisabled: Bool
    ) async throws -> BuildAction
}

struct BuildInsightsActionMapper: BuildInsightsActionMapping {
    func map(
        _ buildAction: BuildAction,
        buildInsightsDisabled: Bool
    ) async throws -> BuildAction {
        guard !buildInsightsDisabled else { return buildAction }

        var buildAction = buildAction
        buildAction.postActions.append(
            ExecutionAction(
                title: "Push build insights",
                scriptText: "\(ServiceContext.current!.environment!.currentExecutablePath()?.pathString ?? "tuist") inspect build",
                target: nil,
                shellPath: nil
            )
        )
        buildAction.runPostActionsOnFailure = true
        return buildAction
    }
}
