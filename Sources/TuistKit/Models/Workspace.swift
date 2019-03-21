import Basic
import Foundation
import TuistCore

class Workspace: Equatable {
    // MARK: - Attributes

    let name: String
    let projects: [AbsolutePath]
    let additionalFiles: [Element]

    // MARK: - Init

    init(name: String, projects: [AbsolutePath], additionalFiles: [Element] = []) {
        self.name = name
        self.projects = projects
        self.additionalFiles = additionalFiles
    }

    // MARK: - Equatable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.projects == rhs.projects
    }
}

extension Workspace {
    func adding(files: [AbsolutePath]) -> Workspace {
        return Workspace(name: name,
                         projects: projects,
                         additionalFiles: additionalFiles + files.map { .file(path: $0) })
    }
}

extension Workspace {
    enum Element: Equatable {
        case file(path: AbsolutePath)
        case folderReference(path: AbsolutePath)

        var path: AbsolutePath {
            switch self {
            case let .file(path):
                return path
            case let .folderReference(path):
                return path
            }
        }
    }
}
