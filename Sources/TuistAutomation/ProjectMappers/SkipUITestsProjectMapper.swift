import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class SkipUITestsProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        project.targets = project.targets.map { target in
            var copy = target
            if copy.product == .uiTests {
                copy.prune = true
            }
            return copy
        }

        return (project, [])
    }
}
