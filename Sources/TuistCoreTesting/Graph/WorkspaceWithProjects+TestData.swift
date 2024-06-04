import Foundation
import TSCBasic
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
@testable import TuistCore

extension WorkspaceWithProjects {
    public static func test(
        workspace: Workspace = .test(),
        projects: [Project] = [.test()]
    ) -> WorkspaceWithProjects {
        WorkspaceWithProjects(
            workspace: workspace,
            projects: projects
        )
    }
}
