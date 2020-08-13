import Foundation

/// An interface to map projects.
public protocol ValueProjectMapping {
    /// Given a project and its targets, it maps them into another project and list of targets.
    /// - Parameters:
    ///   - project: Project to be mapped.
    ///   - targets: List of project targets to be mapped
    func map(project: Project, targets: [String: Target]) throws -> (project: Project, targets: [String: Target], sideEffects: [SideEffectDescriptor])
}

/// A project mapper that is initialized with the mapping function.
public class AnyValueProjectMapper: ValueProjectMapping {
    public typealias ValueProjectMap = (Project, [String: Target]) throws -> (Project, [String: Target], [SideEffectDescriptor])

    /// Mapping function.
    private let mapper: ValueProjectMap

    /// It initializes the mapper with the mapping function.
    /// - Parameter mapper: Mapping function.
    public init(mapper: @escaping ValueProjectMap) {
        self.mapper = mapper
    }

    public func map(project: Project, targets: [String: Target]) throws -> (project: Project, targets: [String: Target], sideEffects: [SideEffectDescriptor]) {
        try mapper(project, targets)
    }
}

/// A project mapper that is initialized with the target mapper.
public class ValueProjectTargetMapper: ValueProjectMapping {
    /// Target mapper.
    private let targetMapper: ValueTargetMapping

    /// Initializes the project mapper with a target mapper.
    /// - Parameter targetMapper: Target mapper.
    public init(targetMapper: ValueTargetMapping) {
        self.targetMapper = targetMapper
    }

    public func map(project: Project, targets: [String: Target]) throws -> (project: Project, targets: [String: Target], sideEffects: [SideEffectDescriptor]) {
        var sideEffects: [SideEffectDescriptor] = []
        var targets: [String: Target] = [:]
        try targets.forEach { _, target in
            let (mappedTarget, targetSideEffects) = try self.targetMapper.map(target: target)
            targets[mappedTarget.name] = mappedTarget
            sideEffects.append(contentsOf: targetSideEffects)
        }
        return (project, [:], sideEffects)
    }
}
