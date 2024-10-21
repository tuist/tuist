import Foundation
import Path
import XcodeGraph
@testable import TuistCore

public final class MockWorkspaceMapper: WorkspaceMapping {
    public var mapStub: ((WorkspaceWithProjects) -> (WorkspaceWithProjects, [SideEffectDescriptor]))?
    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        mapStub?(workspace) ?? (.test(), [])
    }
}
