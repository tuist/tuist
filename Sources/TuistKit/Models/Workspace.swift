import Basic
import Foundation
import TuistCore

class Workspace: Equatable {
    // MARK: - Attributes

    let name: String
    var projects: [AbsolutePath]
    let additionalFiles: [AbsolutePath]

    // MARK: - Init

    init(name: String, projects: [AbsolutePath], additionalFiles: [AbsolutePath]) {
        self.name = name
        self.projects = projects
        self.additionalFiles = additionalFiles
    }

    // MARK: - Equatable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.name == rhs.name && lhs.projects == rhs.projects && lhs.additionalFiles == rhs.additionalFiles
    }
}
