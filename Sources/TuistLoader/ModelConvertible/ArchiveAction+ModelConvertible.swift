import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.ArchiveAction: ModelConvertible {
    init(manifest: ProjectDescription.ArchiveAction, generatorPaths: GeneratorPaths) throws {
        let configurationName = manifest.configurationName
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }

        self.init(configurationName: configurationName,
                  revealArchiveInOrganizer: revealArchiveInOrganizer,
                  customArchiveName: customArchiveName,
                  preActions: preActions,
                  postActions: postActions)
    }
}
