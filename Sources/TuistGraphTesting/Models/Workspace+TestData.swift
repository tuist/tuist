import Foundation
import TSCBasic
@testable import TuistGraph

public extension Workspace {
    static func test(
        path: AbsolutePath = AbsolutePath("/"),
        xcWorkspacePath: AbsolutePath = AbsolutePath("/"),
        name: String = "test",
        projects: [AbsolutePath] = [],
        schemes: [Scheme] = [],
        additionalFiles: [FileElement] = []
    ) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: projects,
            schemes: schemes,
            additionalFiles: additionalFiles
        )
    }
}
