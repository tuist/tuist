import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.ArchiveAction {
    static func from(manifest: ProjectDescription.ArchiveAction,
                     projectPath _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.ArchiveAction {
        let configurationName = manifest.configurationName
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                          generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                            generatorPaths: generatorPaths) }

        return TuistCore.ArchiveAction(configurationName: configurationName,
                                       revealArchiveInOrganizer: revealArchiveInOrganizer,
                                       customArchiveName: customArchiveName,
                                       preActions: preActions,
                                       postActions: postActions)
    }
}
