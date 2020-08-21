import Foundation
import ProjectDescription
import TSCBasic
import TuistSupport

/// A component that can load a manifest and all its (transitive) manifest dependencies
public protocol RecursiveManifestLoading {
    func loadProject(at path: AbsolutePath) throws -> LoadedProjects
    func loadWorkspace(at path: AbsolutePath) throws -> LoadedWorkspace
}

public struct LoadedProjects {
    public var projects: [AbsolutePath: Project]
}

public struct LoadedWorkspace {
    public var path: AbsolutePath
    public var workspace: Workspace
    public var projects: [AbsolutePath: Project]
}

public class RecursiveManifestLoader: RecursiveManifestLoading {
    private let manifestLoader: ManifestLoading
    private let fileHandler: FileHandling
    public init(manifestLoader: ManifestLoading = ManifestLoader(),
                fileHandler: FileHandling = FileHandler.shared)
    {
        self.manifestLoader = manifestLoader
        self.fileHandler = fileHandler
    }

    public func loadProject(at path: AbsolutePath) throws -> LoadedProjects {
        try loadProjects(paths: [path])
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> LoadedWorkspace {
        let workspace = try manifestLoader.loadWorkspace(at: path)

        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let projectPaths = try workspace.projects.map {
            try generatorPaths.resolve(path: $0)
        }.flatMap {
            fileHandler.glob($0, glob: "")
        }.filter {
            fileHandler.isFolder($0)
        }.filter {
            manifestLoader.manifests(at: $0).contains(.project)
        }

        let projects = try loadProjects(paths: projectPaths)
        return LoadedWorkspace(path: path,
                               workspace: workspace,
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
