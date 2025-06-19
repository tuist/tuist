import XcodeGraph

public protocol ProjectMapping {
    func map(project: Project) async throws -> (Project, [SideEffectDescriptor])
}

public class SequentialProjectMapper: ProjectMapping {
    let mappers: [ProjectMapping]

    public init(mappers: [ProjectMapping]) {
        self.mappers = mappers
    }

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        var sideEffects: [SideEffectDescriptor] = []
        for mapper in mappers {
            let (mappedProject, mappedSideEffects) = try await mapper.map(project: project)
            project = mappedProject
            sideEffects.append(contentsOf: mappedSideEffects)
        }

        return (project, sideEffects)
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

#if DEBUG
    final class MockProjectMapper: ProjectMapping {
        var mapStub: ((Project) throws -> (Project, [SideEffectDescriptor]))?
        func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
            try mapStub?(project) ?? (project, [])
        }
    }
#endif
