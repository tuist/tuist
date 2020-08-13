import Foundation
import TSCBasic

/// It defines the interface to map a value graph into another value graph.
public protocol ValueGraphMapping {
    /// Given a graph, it maps it into another graph and a list of side effects.
    /// - Parameter graph: Graph to be mapped.
    func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])
}

/// A value graph mapper that is initialized with the mapping function.
public class AnyValueGraphMapper: ValueGraphMapping {
    let mapper: (ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])

    public init(mapper: @escaping (ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor])) {
        self.mapper = mapper
    }

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        try mapper(graph)
    }
}

/// A type of value graph mapper that is initialized with a project mapper.
public class ValueGraphProjectMapper: ValueGraphMapping {
    /// Project mapper instance.
    private let projectMapper: ValueProjectMapping

    /// Initializes the value graph mapper with a project mapper.
    /// - Parameter projectMapper: Project mapper instance.
    public init(projectMapper: ValueProjectMapping) {
        self.projectMapper = projectMapper
    }

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        var graph = graph
        var sideEffects: [SideEffectDescriptor] = []
        var mappedProjects: [AbsolutePath: Project] = [:]
        var mappedTargets: [AbsolutePath: [String: Target]] = [:]

        try graph.projects.forEach { path, project in
            let (mappedProject, mappedProjectTargets, targetSideEffects) = try self.projectMapper.map(project: project, targets: graph.targets[path] ?? [:])
            mappedProjects[path] = mappedProject
            mappedTargets[path] = mappedProjectTargets
            sideEffects.append(contentsOf: targetSideEffects)
        }

        graph.projects = mappedProjects
        graph.targets = mappedTargets
        return (graph, sideEffects)
    }
}
