import Foundation
import TuistCore
import TuistGraph

public struct ExternalResourcesProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard project.isExternal
        else { return (project, []) }

        var project = project
//        project.targets = project.targets.map { target in
//            guard
//                !target.resources.isEmpty,
//                !target.supportsResources
//            else { return target }
//
//            return target
//        }

        return (project, [])
    }
}
