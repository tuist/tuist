import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class SkipUITestsProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Transforming project \(project.name): Pruning UI tests targets")

        var project = project
        project.targets = project.targets.mapValues { target in
            var copy = target
            if copy.product == .uiTests {
                copy.prune = true
            }
            return copy
        }

        return (project, [])
    }
}
