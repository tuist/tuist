import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.ArchiveAction {
    /// Maps a ProjectDescription.ArchiveAction instance into a TuistGraph.ArchiveAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of archive action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.ArchiveAction, generatorPaths: GeneratorPaths) throws -> TuistGraph
        .ArchiveAction
    {
        let configurationName = manifest.configuration.rawValue
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions
            .map { try TuistGraph.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions
            .map { try TuistGraph.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }

        return TuistGraph.ArchiveAction(
            configurationName: configurationName,
            revealArchiveInOrganizer: revealArchiveInOrganizer,
            customArchiveName: customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }
}
