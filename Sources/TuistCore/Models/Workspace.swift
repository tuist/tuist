import Basic
import Foundation
import TuistSupport

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

    // MARK: - Public

    public func adding(files: [AbsolutePath]) -> Workspace {
        Workspace(name: name,
                  projects: projects,
                  additionalFiles: additionalFiles + files.map { .file(path: $0) })
    }

    public func replacing(projects: [AbsolutePath]) -> Workspace {
        Workspace(name: name,
                  projects: projects,
                  additionalFiles: additionalFiles)
    }

    public func merging(projects otherProjects: [AbsolutePath]) -> Workspace {
        Workspace(name: name,
                  projects: Array(Set(projects + otherProjects)),
                  additionalFiles: additionalFiles)
    }

    // MARK: - Equatable

    public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.projects == rhs.projects
    }
}
