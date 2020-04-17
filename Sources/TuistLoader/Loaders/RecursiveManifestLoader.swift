import Basic
import Foundation
import ProjectDescription
import TuistSupport

public struct LoadedProjectManifest {
    public var path: AbsolutePath
    public var project: Project
}

public struct LoadedWorkspaceManifest {
    public var path: AbsolutePath
    public var workspace: Workspace
}

public protocol RecursiveManifestLoading {
    func loadProject(at path: AbsolutePath) throws -> [LoadedProjectManifest]
    func loadWorkspace(at path: AbsolutePath) throws -> (LoadedWorkspaceManifest, [LoadedProjectManifest])
}

public class RecursiveManifestLoader: RecursiveManifestLoading {
    private let manifestLoader: ManifestLoading
    public init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.manifestLoader = manifestLoader
    }

    public func loadProject(at path: AbsolutePath) throws -> [LoadedProjectManifest] {
        try loadProjects(paths: [path])
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> (LoadedWorkspaceManifest, [LoadedProjectManifest]) {
        let workspace = try manifestLoader.loadWorkspace(at: path)

        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let projectPaths = try workspace.projects.flatMap {
            try generatorPaths.resolve(path: $0)
                .glob("")
                .filter(FileHandler.shared.isFolder)
                .filter {
                    manifestLoader.manifests(at: $0).contains(.project)
                }
        }

        let projects = try loadProjects(paths: projectPaths)
        return (LoadedWorkspaceManifest(path: path, workspace: workspace), projects)
    }

    // MARK: - Private

    private func loadProjects(paths: [AbsolutePath]) throws -> [LoadedProjectManifest] {
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

        return cache.map { LoadedProjectManifest(path: $0.key, project: $0.value) }
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
