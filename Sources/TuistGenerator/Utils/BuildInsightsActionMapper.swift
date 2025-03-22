import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import XcodeGraph

@Mockable
protocol BuildInsightsActionMapping {
    /// Maps a build action to track build insights.
    func map(
        _ buildAction: BuildAction,
        buildInsightsDisabled: Bool,
        path: AbsolutePath
    ) async throws -> BuildAction
}

struct BuildInsightsActionMapper: BuildInsightsActionMapping {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    init(
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    func map(
        _ buildAction: BuildAction,
        buildInsightsDisabled: Bool,
        path: AbsolutePath
    ) async throws -> BuildAction {
        guard !buildInsightsDisabled else { return buildAction }
        let scriptText = if let rootDirectory = try await rootDirectoryLocator.locate(from: path),
                            !(try await miseConfigurationFileExists(at: rootDirectory))
        {
            """
            eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

            tuist inspect build
            """
        } else {
            """
            tuist inspect build
            """
        }

        var buildAction = buildAction
        buildAction.postActions.append(
            ExecutionAction(
                title: "Build insights",
                scriptText: scriptText,
                target: nil,
                shellPath: nil
            )
        )
        buildAction.runPostActionsOnFailure = true
        return buildAction
    }

    private func miseConfigurationFileExists(at path: AbsolutePath) async throws -> Bool {
        try await fileSystem
            .glob(directory: path, include: ["mise.toml", ".mise.toml"])
            .collect()
            .isEmpty
    }
}
