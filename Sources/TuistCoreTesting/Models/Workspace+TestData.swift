import Basic
import Foundation
@testable import TuistCore

public extension Workspace {
    static func test(path: AbsolutePath = AbsolutePath("/"),
                     name: String = "test",
                     projects: [AbsolutePath] = [],
                     additionalFiles: [FileElements] = []) -> Workspace {
        Workspace(path: path,
                  name: name,
                  projects: projects,
                  additionalFiles: additionalFiles)
    }
}
