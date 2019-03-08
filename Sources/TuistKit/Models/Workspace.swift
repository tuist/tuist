import Basic
import Foundation
import TuistCore

class Workspace: Equatable {
    // MARK: - Attributes

    public indirect enum Element: Equatable {
        case file(path: AbsolutePath)
        case group(name: String, contents: [Element])
        case project(path: AbsolutePath)
    }

    let name: String
    let contents: [Element]

    // MARK: - Init

    init(name: String, contents: [Element]) {
        self.name = name
        self.contents = contents
    }

    // MARK: - Equatable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.name == rhs.name && lhs.contents == rhs.contents
    }
}
