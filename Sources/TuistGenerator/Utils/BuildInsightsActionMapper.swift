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
        buildInsightsDisabled: Bool
    ) async throws -> BuildAction
}

struct BuildInsightsActionMapper: BuildInsightsActionMapping {
    private let environment: Environmenting

    init(
        environment: Environmenting = Environment.shared
    ) {
        self.environment = environment
    }

    func map(
        _ buildAction: BuildAction,
        buildInsightsDisabled: Bool
    ) async throws -> BuildAction {
        guard !buildInsightsDisabled else { return buildAction }

        var buildAction = buildAction
        buildAction.postActions.append(
            ExecutionAction(
                title: "Push build insights",
                scriptText: "\(environment.currentExecutablePath().pathString) inspect build",
                target: nil,
                shellPath: nil
            )
        )
        buildAction.runPostActionsOnFailure = true
        return buildAction
    }
}
