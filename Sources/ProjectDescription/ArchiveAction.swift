import Foundation

public struct ArchiveAction: Equatable, Codable {
    public let configuration: ConfigurationName
    public let revealArchiveInOrganizer: Bool
    public let customArchiveName: String?
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    init(
        configuration: ConfigurationName,
        revealArchiveInOrganizer: Bool = true,
        customArchiveName: String? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) {
        self.configuration = configuration
        self.revealArchiveInOrganizer = revealArchiveInOrganizer
        self.customArchiveName = customArchiveName
        self.preActions = preActions
        self.postActions = postActions
    }

    public static func archiveAction(
        configuration: ConfigurationName,
        revealArchiveInOrganizer: Bool = true,
        customArchiveName: String? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> ArchiveAction {
        return ArchiveAction(
            configuration: configuration,
            revealArchiveInOrganizer: revealArchiveInOrganizer,
            customArchiveName: customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }
}
