import Basic
import Foundation
@testable import TuistCore

public extension Workspace {
    static func test(name: String = "test",
                     projects: [AbsolutePath] = [],
                     additionalFiles: [FileElement] = []) -> Workspace {
        Workspace(name: name,
                  projects: projects,
                  additionalFiles: additionalFiles)
    }
}
