import Foundation
import TSCBasic

public struct Workspace: Equatable {
    // MARK: - Attributes

    /// Path to where the manifest / root directory of this workspace is located
    public var path: AbsolutePath
    /// Path to where the `.xcworkspace` will be generated
    public var xcWorkspacePath: AbsolutePath
    public var name: String
    public var projects: [AbsolutePath]
    public var schemes: [Scheme]
    public var additionalFiles: [FileElement]

    // MARK: - Init

    public init(
        path: AbsolutePath,
        xcWorkspacePath: AbsolutePath,
        name: String,
        projects: [AbsolutePath],
        schemes: [Scheme] = [],
        additionalFiles: [FileElement] = []
    ) {
        self.path = path
        self.xcWorkspacePath = xcWorkspacePath
        self.name = name
        self.projects = projects
        self.schemes = schemes
        self.additionalFiles = additionalFiles
    }
}

extension Workspace {
    public func with(name: String) -> Workspace {
        var copy = self
        copy.name = name
        return copy
    }

    public func adding(files: [AbsolutePath]) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: projects,
            schemes: schemes,
            additionalFiles: additionalFiles + files.map { .file(path: $0) }
        )
    }

    public func replacing(projects: [AbsolutePath]) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: projects,
            schemes: schemes,
            additionalFiles: additionalFiles
        )
    }

    public func merging(projects otherProjects: [AbsolutePath]) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: Array(Set(projects + otherProjects)),
            schemes: schemes,
            additionalFiles: additionalFiles
        )
    }
}
