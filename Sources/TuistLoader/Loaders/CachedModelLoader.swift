import Foundation
import TSCBasic
import TuistCore

/// An in-memory model loader implementation which can be configured
/// at instantiation time with a cache of all preloaded models.
public class CachedModelLoader: GeneratorModelLoading {
    private let workspaces: [AbsolutePath: Workspace]
    private let projects: [AbsolutePath: Project]
    private let configs: [AbsolutePath: Config]
    public init(workspace: [Workspace] = [],
                projects: [Project] = [],
                configs: [AbsolutePath: Config] = [:])
    {
        workspaces = Dictionary(uniqueKeysWithValues: workspace.map {
            ($0.path, $0)
        })
        self.projects = Dictionary(uniqueKeysWithValues: projects.map {
            ($0.path, $0)
        })
        self.configs = configs
    }

    public func loadProject(at path: AbsolutePath) throws -> Project {
        guard let project = projects[path] else {
            throw ManifestLoaderError.manifestNotFound(.project, path)
        }
        return project
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        guard let workspace = workspaces[path] else {
            throw ManifestLoaderError.manifestNotFound(.workspace, path)
        }
        return workspace
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        guard let config = configs[path] else {
            throw ManifestLoaderError.manifestNotFound(.config, path)
        }
        return config
    }
}
