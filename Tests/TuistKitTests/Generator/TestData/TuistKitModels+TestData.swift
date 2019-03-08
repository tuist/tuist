import Basic
@testable import TuistKit

extension Workspace {
    static func test(name: String = "test", contents: [Workspace.Element] = []) -> Workspace {
        return Workspace(name: name, contents: contents)
    }

    static func test(name: String = "test", projects: [AbsolutePath] = []) -> Workspace {
        return Workspace(name: name, contents: projects.map(Workspace.Element.project))
    }
}
