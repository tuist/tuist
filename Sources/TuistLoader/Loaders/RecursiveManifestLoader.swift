import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport

/// A component that can load a manifest and all its (transitive) manifest dependencies
public protocol RecursiveManifestLoading {
    func loadWorkspace(at path: AbsolutePath) throws -> LoadedWorkspace
}

public struct LoadedProjects {
    public var projects: [AbsolutePath: ProjectDescription.Project]
}

public struct LoadedWorkspace {
    public var path: AbsolutePath
    public var workspace: ProjectDescription.Workspace
    public var projects: [AbsolutePath: ProjectDescription.Project]
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

    public func loadWorkspace(at path: AbsolutePath) throws -> LoadedWorkspace {
        var workspace: ProjectDescription.Workspace
        do {
            workspace = try manifestLoader.loadWorkspace(at: path)
        } catch ManifestLoaderError.manifestNotFound {
            workspace = Workspace(name: "Workspace", projects: ["."])
        }

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
        if let workspaceName = projects.projects[path]?.name {
            workspace = Workspace(name: workspaceName, projects: ["."])
        }
        return LoadedWorkspace(
            path: path,
            workspace: workspace,
            projects: projects.projects
        )
    }

    // MARK: - Private

    private func loadProjects(paths: [AbsolutePath]) throws -> LoadedProjects {
        var cache = [AbsolutePath: ProjectDescription.Project]()

        var paths = Set(paths)
        while !paths.isEmpty {
            paths.subtract(cache.keys)
            let projects = try Array(paths).map(context: ExecutionContext.concurrent) {
                try manifestLoader.loadProject(at: $0)
            }
            var newDependenciesPaths = Set<AbsolutePath>()
            try zip(paths, projects).forEach { path, project in
                cache[path] = project
                newDependenciesPaths.formUnion(try dependencyPaths(for: project, path: path))
            }
            paths = newDependenciesPaths
        }
        return LoadedProjects(projects: cache)
    }

    private func dependencyPaths(for project: ProjectDescription.Project, path: AbsolutePath) throws -> [AbsolutePath] {
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
