import Foundation

// MARK: - Scheme

public struct Scheme: Equatable, Codable {
    public let name: String
    public let shared: Bool
    public let hidden: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?
    public let archiveAction: ArchiveAction?
    public let profileAction: ProfileAction?
    public let analyzeAction: AnalyzeAction?

    /// Creates a new instance of a scheme.
    /// - Parameters:
    ///   - name: Name of the scheme.
    ///   - shared: Whether the scheme is shared.
    ///   - hidden: When true, the scheme is hidden in the list of schemes from Xcode's dropdown.
    ///   - buildAction: Scheme's build action.
    ///   - testAction: Scheme's test action.
    ///   - runAction: Scheme's run action.
    ///   - archiveAction: Scheme's archive action.
    ///   - profileAction: Scheme's profile action.
    ///   - analyzeAction: Scheme's analyze action.
    public init(name: String,
                shared: Bool = true,
                hidden: Bool = false,
                buildAction: BuildAction? = nil,
                testAction: TestAction? = nil,
                runAction: RunAction? = nil,
                archiveAction: ArchiveAction? = nil,
                profileAction: ProfileAction? = nil,
                analyzeAction: AnalyzeAction? = nil)
    {
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
