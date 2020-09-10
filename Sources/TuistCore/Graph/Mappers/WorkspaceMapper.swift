import Foundation

public protocol WorkspaceMapping {
    func map(workspace: Workspace, graph: Graph) throws -> (Workspace, [SideEffectDescriptor])
}

public class SequentialWorkspaceMapper: WorkspaceMapping {
    let mappers: [WorkspaceMapping]

    public init(mappers: [WorkspaceMapping]) {
        self.mappers = mappers
    }

    public func map(workspace: Workspace, graph: Graph) throws -> (Workspace, [SideEffectDescriptor]) {
        var results = (workspace: workspace, sideEffects: [SideEffectDescriptor]())
        results = try mappers.reduce(into: results) { results, mapper in
            let (updatedWorkspace, sideEffects) = try mapper.map(workspace: results.workspace, graph: graph)
            results.workspace = updatedWorkspace
            results.sideEffects.append(contentsOf: sideEffects)
        }
        return results
    }
}
