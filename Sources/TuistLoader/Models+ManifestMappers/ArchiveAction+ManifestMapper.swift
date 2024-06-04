import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.ArchiveAction {
    /// Maps a ProjectDescription.ArchiveAction instance into a XcodeProjectGenerator.ArchiveAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of archive action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.ArchiveAction, generatorPaths: GeneratorPaths) throws -> XcodeProjectGenerator
        .ArchiveAction
    {
        let configurationName = manifest.configuration.rawValue
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions
            .map { try XcodeProjectGenerator.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions
            .map { try XcodeProjectGenerator.ExecutionAction.from(manifest: $0, generatorPaths: generatorPaths) }

        return XcodeProjectGenerator.ArchiveAction(
            configurationName: configurationName,
            revealArchiveInOrganizer: revealArchiveInOrganizer,
            customArchiveName: customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }
}
