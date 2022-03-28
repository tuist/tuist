import TuistCore
import TuistGraph

/// This mapper takes the `Project` `disableShowEnvironmentVarsInScriptPhases` option and pushes it down into all of the `Target`s shell script `TargetAction`s
public final class TargetActionDisableShowEnvVarsProjectMapper: ProjectMapping { // swiftlint:disable:this type_name
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        project.targets = project.targets.map { target in
            var mappedTarget = target
            mappedTarget.scripts = mappedTarget.scripts.map {
                var script = $0
                script.showEnvVarsInLog = !project.options.disableShowEnvironmentVarsInScriptPhases
                return script
            }
            return mappedTarget
        }

        return (project, [])
    }
}
