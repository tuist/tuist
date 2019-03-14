import Basic
@testable import TuistKit

extension Workspace {
    static func test(name: String = "test", projects: [AbsolutePath] = [], additionalFiles: [AbsolutePath] = []) -> Workspace {
        return Workspace(name: name, projects: projects, additionalFiles: additionalFiles)
    }
}
