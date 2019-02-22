import Basic
import Foundation
import TuistCore

class Workspace: Equatable {
    // MARK: - Attributes

    let name: String
    let projects: [AbsolutePath]

    // MARK: - Init

    init(name: String, projects: [AbsolutePath]) {
        self.name = name
        self.projects = projects
    }

    // MARK: - Equatable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.projects == rhs.projects
    }
}
