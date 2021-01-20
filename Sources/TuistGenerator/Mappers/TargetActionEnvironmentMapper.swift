import TuistCore
import TuistGraph

/// This mapper takes the `Config`level setting `disableShowEnvironmentVarsInScriptPhases` and pushes it down into all of the `Project`'s shell script `TargetAction`s`

public final class TargetActionEnvironmentMapper: TargetMapping {
    let showEnvVarsInLog: Bool

    public init(_ showEnvVarsInLog: Bool) {
        self.showEnvVarsInLog = showEnvVarsInLog
    }

    public func map(target: Target) throws -> (Target, [SideEffectDescriptor]) {
        var target = target
        let actions: [TargetAction] = target.actions.map {
            var action = $0
            action.showEnvVarsInLog = showEnvVarsInLog
            return action
        }
        target.actions = actions
        return (target, [SideEffectDescriptor]())
    }
}
