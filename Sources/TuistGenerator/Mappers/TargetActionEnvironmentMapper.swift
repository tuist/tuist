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
        let scripts: [TargetScript] = target.scripts.map {
            var script = $0
            script.showEnvVarsInLog = showEnvVarsInLog
            return script
        }
        target.scripts = scripts
        return (target, [SideEffectDescriptor]())
    }
}
