import XcodeGraph

extension Scheme {
    public func targetDependencies() -> [TargetReference] {
        let targetSources: [[TargetReference]?] = [
            buildAction?.targets,
            buildAction?.preActions.compactMap(Self.referencedTarget),
            buildAction?.postActions.compactMap(Self.referencedTarget),
            testAction?.targets.map(\.target),
            testAction?.codeCoverageTargets,
            testAction?.preActions.compactMap(Self.referencedTarget),
            testAction?.postActions.compactMap(Self.referencedTarget),
            runAction?.executable.map { [$0] },
            archiveAction?.preActions.compactMap(Self.referencedTarget),
            archiveAction?.postActions.compactMap(Self.referencedTarget),
            profileAction?.executable.map { [$0] },
        ]

        let targets = targetSources.compactMap { $0 }.flatMap { $0 }.uniqued()
        return targets.sorted { $0.name < $1.name }
    }

    private static func referencedTarget(_ action: ExecutionAction) -> TargetReference? {
        if case let .target(ref) = action.target { return ref }
        return nil
    }
}
