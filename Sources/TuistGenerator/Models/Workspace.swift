import Basic
import Foundation
import TuistCore

public class Workspace: Equatable {
    // MARK: - Attributes

    public let name: String
    public let projects: [AbsolutePath]
    public let additionalFiles: [Element]

    // MARK: - Init

    public init(name: String, projects: [AbsolutePath], additionalFiles: [Element] = []) {
        self.name = name
        self.projects = projects
        self.additionalFiles = additionalFiles
    }

    // MARK: - Equatable

    public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.projects == rhs.projects
    }
}

extension Workspace {
    func adding(files: [AbsolutePath]) -> Workspace {
        return Workspace(name: name,
                         projects: projects,
                         additionalFiles: additionalFiles + files.map { .file(path: $0) })
    }

    func replacing(projects: [AbsolutePath]) -> Workspace {
        return Workspace(name: name,
                         projects: projects,
                         additionalFiles: additionalFiles)
    }

    func merging(projects otherProjects: [AbsolutePath]) -> Workspace {
        return Workspace(name: name,
                         projects: Array(Set(projects + otherProjects)),
                         additionalFiles: additionalFiles)
    }
}

extension Workspace {
    public enum Element: Equatable {
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
