import Foundation
import TSCBasic
@testable import TuistCore

public extension WorkspaceWithProjects {
    static func test() -> WorkspaceWithProjects {
        WorkspaceWithProjects(workspace: .test(), projects: [.test()])
    }
}
