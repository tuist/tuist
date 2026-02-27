import Foundation
import Path

public struct ArchiveAction: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public let configurationName: String
    public let revealArchiveInOrganizer: Bool
    public let customArchiveName: String?
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(
        configurationName: String,
        revealArchiveInOrganizer: Bool = true,
        customArchiveName: String? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) {
        self.configurationName = configurationName
        self.revealArchiveInOrganizer = revealArchiveInOrganizer
        self.customArchiveName = customArchiveName
        self.preActions = preActions
        self.postActions = postActions
    }
}

#if DEBUG
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
#endif
