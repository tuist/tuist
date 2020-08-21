import Foundation
import TSCBasic
@testable import TuistCore

public extension Workspace {
    static func test(path: AbsolutePath = AbsolutePath("/"),
                     name: String = "test",
                     projects: [AbsolutePath] = [],
                     additionalFiles: [FileElement] = []) -> Workspace
    {
        Workspace(path: path,
                  name: name,
                  projects: projects,
                  additionalFiles: additionalFiles)
    }
}
