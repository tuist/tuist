import Basic
import Foundation
import TuistSupport

public class Workspace: Equatable {
    // MARK: - Attributes

    public let path: AbsolutePath
    public let name: String
    public let projects: [AbsolutePath]
    public let schemes: [Scheme]
    public let additionalFiles: [FileElement]

    // MARK: - Init

    public init(path: AbsolutePath, name: String, projects: [AbsolutePath], schemes: [Scheme] = [], additionalFiles: [FileElement] = []) {
        self.path = path
        self.name = name
        self.projects = projects
        self.schemes = schemes
        self.additionalFiles = additionalFiles
    }
}

extension Workspace {
    public func adding(files: [AbsolutePath]) -> Workspace {
        return Workspace(path: path,
                         name: name,
                         projects: projects,
                         schemes: schemes,
                         additionalFiles: additionalFiles + files.map { .file(path: $0) })
    }
    
    public func replacing(projects: [AbsolutePath]) -> Workspace {
        return Workspace(path: path,
                         name: name,
                         projects: projects,
                         schemes: schemes,
                         additionalFiles: additionalFiles)
    }
    
    public func merging(projects otherProjects: [AbsolutePath]) -> Workspace {
        return Workspace(path: path,
                         name: name,
                         projects: Array(Set(projects + otherProjects)),
                         schemes: schemes,
                         additionalFiles: additionalFiles)
    }

    // MARK: - Equatable

    public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.projects == rhs.projects
    }
}
