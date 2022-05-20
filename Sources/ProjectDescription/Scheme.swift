import Foundation

/// A custom scheme for a project.
///
/// A scheme defines a collection of targets to Build, Run, Test, Profile, Analyze and Archive.
public struct Scheme: Equatable, Codable {
    /// The name of the scheme.
    public let name: String
    /// Marks the scheme as shared (i.e. one that is checked in to the repository and is visible to xcodebuild from the command line).
    public let shared: Bool
    /// When `true` the scheme doesn't show up in the dropdown scheme's list.
    public let hidden: Bool
    /// Action that builds the project targets.
    public let buildAction: BuildAction?
    /// Action that runs the project tests.
    public let testAction: TestAction?
    /// Action that runs project built products.
    public let runAction: RunAction?
    /// Action that runs the project archive.
    public let archiveAction: ArchiveAction?
    /// Action that profiles the project.
    public let profileAction: ProfileAction?
    /// Action that analyze the project.
    public let analyzeAction: AnalyzeAction?

    /// Creates a new instance of a scheme.
    /// - Parameters:
    ///   - name: Name of the scheme.
    ///   - shared: Whether the scheme is shared.
    ///   - hidden: When true, the scheme is hidden in the list of schemes from Xcode's dropdown.
    ///   - buildAction: Action that builds the project targets.
    ///   - testAction: Action that runs the project tests.
    ///   - runAction: Action that runs project built products.
    ///   - archiveAction: Action that runs the project archive.
    ///   - profileAction: Action that profiles the project.
    ///   - analyzeAction: Action that analyze the project.
    public init(
        name: String,
        shared: Bool = true,
        hidden: Bool = false,
        buildAction: BuildAction? = nil,
        testAction: TestAction? = nil,
        runAction: RunAction? = nil,
        archiveAction: ArchiveAction? = nil,
        profileAction: ProfileAction? = nil,
        analyzeAction: AnalyzeAction? = nil
    ) {
        self.name = name
        self.shared = shared
        self.hidden = hidden
        self.buildAction = buildAction
        self.testAction = testAction
        self.runAction = runAction
        self.archiveAction = archiveAction
        self.profileAction = profileAction
        self.analyzeAction = analyzeAction
    }
}
