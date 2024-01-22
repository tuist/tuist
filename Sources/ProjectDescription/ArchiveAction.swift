import Foundation

/// An action that archives the built products.
public struct ArchiveAction: Equatable, Codable {
    /// Indicates the build configuration to run the archive with.
    public var configuration: ConfigurationName
    /// If set to true, Xcode will reveal the Organizer on completion.
    public var revealArchiveInOrganizer: Bool
    /// Set if you want to override Xcode's default archive name.
    public var customArchiveName: String?
    /// A list of actions that are executed before starting the archive process.
    public var preActions: [ExecutionAction]
    /// A list of actions that are executed after the archive process.
    public var postActions: [ExecutionAction]

    public init(
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
}
