import Foundation
import TSCBasic
@testable import TuistGraph

extension ArchiveAction {
    public static func test(
        configurationName: String = "Beta Release",
        revealArchiveInOrganizer: Bool = true,
        customArchiveName: String? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> ArchiveAction {
        ArchiveAction(
            configurationName: configurationName,
            revealArchiveInOrganizer: revealArchiveInOrganizer,
            customArchiveName: customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }
}
