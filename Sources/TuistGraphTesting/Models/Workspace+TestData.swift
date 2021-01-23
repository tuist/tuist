import Foundation
import TSCBasic
@testable import TuistGraph

public extension Workspace {
    static func test(
        path: AbsolutePath = AbsolutePath("/"),
        name: String = "test",
        projects: [AbsolutePath] = [],
        xcodeProjPaths: [AbsolutePath] = [],
        schemes: [Scheme] = [],
        additionalFiles: [FileElement] = []
    ) -> Workspace {
        Workspace(
            path: path,
            name: name,
            projects: projects,
            xcodeProjPaths: xcodeProjPaths,
            schemes: schemes,
            additionalFiles: additionalFiles
        )
    }
}
