import Basic
import Foundation
import ProjectDescription

public struct LoadedProjects {
    public var projects: [AbsolutePath: Project]
}

public struct LoadedWorkspace {
    public var workspace: (AbsolutePath, Workspace)
    public var projects: [AbsolutePath: Project]
}

public protocol RecursiveManifestLoading {
    func loadProject(at path: AbsolutePath) throws -> LoadedProjects
    func loadWorkspace(at path: AbsolutePath) throws -> LoadedWorkspace
}

public class RecursiveManifestLoader: RecursiveManifestLoading {
    private let manifestLoader: ManifestLoading
    public init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.manifestLoader = manifestLoader
    }

    public func loadProject(at path: AbsolutePath) throws -> LoadedProjects {
        try loadProjects(paths: [path])
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> LoadedWorkspace {
        let workspace = try manifestLoader.loadWorkspace(at: path)

        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let projectPaths = try workspace.projects.map {
            try generatorPaths.resolve(path: $0)
        }

        let projects = try loadProjects(paths: projectPaths)
        return LoadedWorkspace(workspace: (path, workspace),
                               projects: projects.projects)
    }

    // MARK: - Private

    private func loadProjects(paths: [AbsolutePath]) throws -> LoadedProjects {
        var cache = [AbsolutePath: Project]()

        var paths = paths
        while let path = paths.popLast() {
            guard cache[path] == nil else {
                continue
            }

            let project = try manifestLoader.loadProject(at: path)
            cache[path] = project
            paths.append(contentsOf: try dependencyPaths(for: project, path: path))
        }

        return LoadedProjects(projects: cache)
    }

    private func dependencyPaths(for project: Project, path: AbsolutePath) throws -> [AbsolutePath] {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let paths: [AbsolutePath] = try project.targets.flatMap {
            try $0.dependencies.compactMap {
                switch $0 {
                case let .project(target: _, path: projectPath):
                    return try generatorPaths.resolve(path: projectPath)
                default:
                    return nil
                }
            }
        }
        return paths.uniqued()
    }
}
