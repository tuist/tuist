import Logging
import TuistCore
import XcodeGraph

public final class SkipUITestsProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        Logger.current.debug("Transforming project \(project.name): Pruning UI tests targets")

        var project = project
        project.targets = project.targets.mapValues { target in
            var copy = target
            if copy.product == .uiTests {
                copy.metadata.tags.formUnion(["tuist:prunable"])
            }
            return copy
        }

        return (project, [])
    }
}
