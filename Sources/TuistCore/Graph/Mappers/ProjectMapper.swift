import Foundation
import XcodeGraph

public protocol ProjectMapping {
    func map(project: Project) throws -> (Project, [SideEffectDescriptor])
}

public class SequentialProjectMapper: ProjectMapping {
    let mappers: [ProjectMapping]

    public init(mappers: [ProjectMapping]) {
        self.mappers = mappers
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var results = (project: project, sideEffects: [SideEffectDescriptor]())
        results = try mappers.reduce(into: results) { results, mapper in
            let (updatedProject, sideEffects) = try mapper.map(project: results.project)
            results.project = updatedProject
            results.sideEffects.append(contentsOf: sideEffects)
        }
        return results
    }
}

public class TargetProjectMapper: ProjectMapping {
    private let mapper: TargetMapping

    public init(mapper: TargetMapping) {
        self.mapper = mapper
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var results = (targets: [String: Target](), sideEffects: [SideEffectDescriptor]())
        results = try project.targets.values.reduce(into: results) { results, target in
            let (updatedTarget, sideEffects) = try mapper.map(target: target)
            results.targets[updatedTarget.name] = updatedTarget
            results.sideEffects.append(contentsOf: sideEffects)
        }
        var project = project
        project.targets = results.targets

        return (project, results.sideEffects)
    }
}
