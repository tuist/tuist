import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.ArchiveAction {
    /// Maps a ProjectDescription.ArchiveAction instance into a TuistCore.ArchiveAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of archive action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.ArchiveAction, generatorPaths: GeneratorPaths) throws -> TuistCore.ArchiveAction {
        let configurationName = manifest.configurationName
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }

        return TuistCore.ArchiveAction(configurationName: configurationName,
                                       revealArchiveInOrganizer: revealArchiveInOrganizer,
                                       customArchiveName: customArchiveName,
                                       preActions: preActions,
                                       postActions: postActions)
    }
}
