import Basic
import Foundation
import TuistCore

public class Workspace: Equatable {
    // MARK: - Attributes

    public let name: String
    public let projects: [AbsolutePath]
    public let additionalFiles: [FileElement]

    // MARK: - Init

    public init(name: String, projects: [AbsolutePath], additionalFiles: [FileElement] = []) {
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
