/// A custom scheme for a project.
///
/// A scheme defines a collection of targets to Build, Run, Test, Profile, Analyze and Archive.
public struct Scheme: Equatable, Codable, Sendable {
    /// The name of the scheme.
    public var name: String
    /// Marks the scheme as shared (i.e. one that is checked in to the repository and is visible to xcodebuild from the command
    /// line).
    public var shared: Bool
    /// When `true` the scheme doesn't show up in the dropdown scheme's list.
    public var hidden: Bool
    /// The position of the scheme in Xcode's scheme list. Schemes with an order hint are listed first, in ascending order,
    /// followed by the rest in alphabetical order. Schemes with the same order hint are listed alphabetically. Xcode falls
    /// back to the first scheme in the list when none is selected, for example in a freshly generated workspace.
    public var orderHint: Int?
    /// Action that builds the project targets.
    public var buildAction: BuildAction?
    /// Action that runs the project tests.
    public var testAction: TestAction?
    /// Action that runs project built products.
    public var runAction: RunAction?
    /// Action that runs the project archive.
    public var archiveAction: ArchiveAction?
    /// Action that profiles the project.
    public var profileAction: ProfileAction?
    /// Action that analyze the project.
    public var analyzeAction: AnalyzeAction?

    /// Creates a new instance of a scheme.
    /// - Parameters:
    ///   - name: Name of the scheme.
    ///   - shared: Whether the scheme is shared.
    ///   - hidden: When true, the scheme is hidden in the list of schemes from Xcode's dropdown.
    ///   - orderHint: The position of the scheme in Xcode's scheme list. When `nil`, the scheme is listed alphabetically
    ///     after the schemes that have one.
    ///   - buildAction: Action that builds the project targets.
    ///   - testAction: Action that runs the project tests.
    ///   - runAction: Action that runs project built products.
    ///   - archiveAction: Action that runs the project archive.
    ///   - profileAction: Action that profiles the project.
    ///   - analyzeAction: Action that analyze the project.
    public static func scheme(
        name: String,
        shared: Bool = true,
        hidden: Bool = false,
        orderHint: Int? = nil,
        buildAction: BuildAction? = nil,
        testAction: TestAction? = nil,
        runAction: RunAction? = nil,
        archiveAction: ArchiveAction? = nil,
        profileAction: ProfileAction? = nil,
        analyzeAction: AnalyzeAction? = nil
    ) -> Self {
        self.init(
            name: name,
            shared: shared,
            hidden: hidden,
            orderHint: orderHint,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction,
            archiveAction: archiveAction,
            profileAction: profileAction,
            analyzeAction: analyzeAction
        )
    }
}
