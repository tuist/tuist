/// An action that archives the built products.
///
/// It's initialized with the `.archiveAction` static method.
public struct ArchiveAction: Equatable, Codable, Sendable {
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

    /// Initialize a `ArchiveAction`
    /// - Parameters:
    ///   - configuration: Indicates the build configuration to run the archive with.
    ///   - revealArchiveInOrganizer: If set to true, Xcode will reveal the Organizer on completion.
    ///   - customArchiveName: Set if you want to override Xcode's default archive name.
    ///   - preActions: A list of actions that are executed before starting the archive process.
    ///   - postActions: A list of actions that are executed after the archive process.
    public static func archiveAction(
        configuration: ConfigurationName,
        revealArchiveInOrganizer: Bool = true,
        customArchiveName: String? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> ArchiveAction {
        ArchiveAction(
            configuration: configuration,
            revealArchiveInOrganizer: revealArchiveInOrganizer,
            customArchiveName: customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }
}
