import Foundation
import TSCBasic

public struct Scheme: Equatable, Codable {
    // MARK: - Attributes

    public var name: String
    public var shared: Bool
    public var hidden: Bool
    public var buildAction: BuildAction?
    public var testAction: TestAction?
    public var runAction: RunAction?
    public var archiveAction: ArchiveAction?
    public var profileAction: ProfileAction?
    public var analyzeAction: AnalyzeAction?

    // MARK: - Init

    public init(
        name: String,
        shared: Bool = false,
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
