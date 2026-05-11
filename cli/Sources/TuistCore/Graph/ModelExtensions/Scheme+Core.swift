import XcodeGraph

extension Scheme {
    public func targetDependencies() -> [TargetReference] {
        func referencedTarget(_ action: ExecutionAction) -> TargetReference? {
            if case let .target(ref) = action.target { return ref }
            return nil
        }
        let targetSources: [[TargetReference]?] = [
            buildAction?.targets,
            buildAction?.preActions.compactMap(referencedTarget),
            buildAction?.postActions.compactMap(referencedTarget),
            testAction?.targets.map(\.target),
            testAction?.codeCoverageTargets,
            testAction?.preActions.compactMap(referencedTarget),
            testAction?.postActions.compactMap(referencedTarget),
            runAction?.executable.map { [$0] },
            archiveAction?.preActions.compactMap(referencedTarget),
            archiveAction?.postActions.compactMap(referencedTarget),
            profileAction?.executable.map { [$0] },
        ]

        let targets = targetSources.compactMap { $0 }.flatMap { $0 }.uniqued()
        return targets.sorted { $0.name < $1.name }
    }
}
