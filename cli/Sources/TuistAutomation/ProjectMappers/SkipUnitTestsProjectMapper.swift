import Logging
import TuistCore
import XcodeGraph

public struct SkipUnitTestsProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        Logger.current.debug("Transforming project \(project.name): Pruning Unit tests targets")

        var project = project
        project.targets = project.targets.mapValues { target in
            var copy = target
            if copy.product == .unitTests {
                copy.metadata.tags.formUnion(["tuist:prunable"])
            }
            return copy
        }

        return (project, [])
    }
}
