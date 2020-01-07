import Basic
import Foundation

public struct ArchiveAction: Equatable {
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

    // MARK: - Equatable

    public static func == (lhs: ArchiveAction, rhs: ArchiveAction) -> Bool {
        lhs.configurationName == rhs.configurationName
            && lhs.revealArchiveInOrganizer == rhs.revealArchiveInOrganizer
            && lhs.customArchiveName == rhs.customArchiveName
            && lhs.preActions == rhs.preActions
            && lhs.postActions == rhs.postActions
    }
}
