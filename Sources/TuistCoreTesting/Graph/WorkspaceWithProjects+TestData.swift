import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

public extension WorkspaceWithProjects {
    static func test(
        workspace: Workspace = .test(),
        projects: [Project] = [.test()]
    ) -> WorkspaceWithProjects {
        WorkspaceWithProjects(
            workspace: workspace,
            projects: projects
        )
    }
}
