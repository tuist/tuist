import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.ArchiveAction {
    /// Maps a ProjectDescription.ArchiveAction instance into a XcodeGraph.ArchiveAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of archive action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.ArchiveAction, generatorPaths: GeneratorPaths) throws -> XcodeGraph
        .ArchiveAction
    {
        let configurationName = manifest.configuration.rawValue
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions
            .map { try XcodeGraph.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions
            .map { try XcodeGraph.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }

        return XcodeGraph.ArchiveAction(
            configurationName: configurationName,
            revealArchiveInOrganizer: revealArchiveInOrganizer,
            customArchiveName: customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }
}
