import Basic
import Foundation

public struct Scheme: Equatable {
    // MARK: - Attributes

    public let name: String
    public let shared: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?
    public let archiveAction: ArchiveAction?

    // MARK: - Init

    public init(name: String,
                shared: Bool = false,
                buildAction: BuildAction? = nil,
                testAction: TestAction? = nil,
                runAction: RunAction? = nil,
                archiveAction: ArchiveAction? = nil) {
        self.name = name
        self.shared = shared
        self.buildAction = buildAction
        self.testAction = testAction
        self.runAction = runAction
        self.archiveAction = archiveAction
    }
    
    public func targetDependencies() -> [TargetReference] {
        let targetSources: [[TargetReference]?] = [
            buildAction?.targets,
            buildAction?.preActions.compactMap(\.target),
            buildAction?.postActions.compactMap(\.target),
            testAction?.targets.map(\.target),
            testAction?.codeCoverageTargets,
            testAction?.preActions.compactMap(\.target),
            testAction?.postActions.compactMap(\.target),
            runAction?.executable.map { [$0] },
            archiveAction?.preActions.compactMap(\.target),
            archiveAction?.postActions.compactMap(\.target)
        ]
        
        let targets = targetSources.compactMap { $0 }.flatMap { $0 }.uniqued()
        return targets.sorted { ($0.name < $1.name) }
    }
}
