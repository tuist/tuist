import XcodeGraph

extension Scheme {
    public func targetDependencies() -> [TargetReference] {
        let targets = (nonCodeCoverageTargetDependencies() + (testAction?.codeCoverageTargets ?? [])).uniqued()
        return targets.sorted { $0.name < $1.name }
    }

    /// Returns the target references used by the scheme actions, excluding the test action's
    /// code coverage targets, which can reference targets that are not part of the graph
    /// (e.g. local Swift package targets).
    public func nonCodeCoverageTargetDependencies() -> [TargetReference] {
        let targetSources: [[TargetReference]?] = [
            buildAction?.targets,
            buildAction?.preActions.compactMap(\.target),
            buildAction?.postActions.compactMap(\.target),
            testAction?.targets.map(\.target),
            testAction?.preActions.compactMap(\.target),
            testAction?.postActions.compactMap(\.target),
            runAction?.executable.map { [$0] },
            archiveAction?.preActions.compactMap(\.target),
            archiveAction?.postActions.compactMap(\.target),
            profileAction?.executable.map { [$0] },
        ]

        let targets = targetSources.compactMap { $0 }.flatMap { $0 }.uniqued()
        return targets.sorted { $0.name < $1.name }
    }
}
