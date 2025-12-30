import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

/// A component that can load a manifest and all its (transitive) manifest dependencies
public protocol RecursiveManifestLoading {
    /// Load manifest at path
    /// - Parameters:
    ///   - path: Path of the manifest
    ///   - disableSandbox: Whether to disable loading the manifest in a sandboxed environment.
    /// - Returns: Loaded manifest
    func loadWorkspace(
        at path: AbsolutePath,
        disableSandbox: Bool
    ) async throws -> LoadedWorkspace

    /// Load package projects and merge in the loaded manifest
    /// - Parameters:
    ///   - loadedWorkspace: manifest to merge in
    ///   - packageSettings: custom SPM settings
    ///   - disableSandbox: Whether to disable loading the manifest in a sandboxed environment.
    /// - Returns: Loaded manifest
    func loadAndMergePackageProjects(
        in loadedWorkspace: LoadedWorkspace,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool
    ) async throws -> LoadedWorkspace
}

public struct LoadedProjects {
    public var projects: [AbsolutePath: ProjectDescription.Project]
}

public struct LoadedWorkspace {
    public var path: AbsolutePath
    public var workspace: ProjectDescription.Workspace
    public var projects: [AbsolutePath: ProjectDescription.Project]
}

public struct RecursiveManifestLoader: RecursiveManifestLoading {
    private let manifestLoader: ManifestLoading
    private let fileHandler: FileHandling
    private let fileSystem: FileSysteming
    private let packageInfoMapper: PackageInfoMapping
    private let rootDirectoryLocator: RootDirectoryLocating

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileHandler: FileHandling = FileHandler.shared,
        fileSystem: FileSysteming = FileSystem(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.manifestLoader = manifestLoader
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
        self.packageInfoMapper = packageInfoMapper
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func loadWorkspace(at path: AbsolutePath, disableSandbox: Bool) async throws -> LoadedWorkspace {
        let loadedWorkspace: ProjectDescription.Workspace?
        do {
            loadedWorkspace = try await manifestLoader.loadWorkspace(at: path, disableSandbox: disableSandbox)
        } catch ManifestLoaderError.manifestNotFound {
            loadedWorkspace = nil
        }
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: rootDirectory
        )
        let projectSearchPaths = (loadedWorkspace?.projects ?? ["."])
        let projectPaths = try await projectSearchPaths.map {
            try generatorPaths.resolve(path: $0)
        }.concurrentFlatMap {
            try await fileSystem.glob(
                directory: AbsolutePath.root,
                include: [
                    String($0.appending(component: Manifest.project.fileName($0)).pathString.dropFirst()),
                ]
            )
            .collect()
            .map(\.parentDirectory)
        }

        let projects = await LoadedProjects(
            projects: try loadProjects(paths: projectPaths, disableSandbox: disableSandbox)
                .projects
        )
        let workspace: ProjectDescription.Workspace
        if let loadedWorkspace {
            workspace = loadedWorkspace
        } else {
            let projectName = projects.projects[path]?.name
            let workspaceName = projectName ?? "Workspace"
            workspace = Workspace(name: workspaceName, projects: projectSearchPaths)
        }
        return LoadedWorkspace(
            path: path,
            workspace: workspace,
            projects: projects.projects
        )
    }

    public func loadAndMergePackageProjects(
        in loadedWorkspace: LoadedWorkspace,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool
    ) async throws -> LoadedWorkspace {
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: loadedWorkspace.path)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: loadedWorkspace.path,
            rootDirectory: rootDirectory
        )
        let projectSearchPaths = loadedWorkspace.workspace.projects.isEmpty ? ["."] : loadedWorkspace.workspace.projects
        let manifestLoader = manifestLoader
        let packagePaths = try await projectSearchPaths.map {
            try generatorPaths.resolve(path: $0)
        }.concurrentFlatMap {
            try await fileSystem.glob(directory: $0, include: [""]).collect()
        }.filter {
            fileHandler.isFolder($0) && $0.basename != Constants.tuistDirectoryName
        }.concurrentFilter {
            let manifests = try await manifestLoader.manifests(at: $0)
            return manifests.contains(.package) && !manifests.contains(.project) && !manifests.contains(.workspace) && !$0
                .pathString.contains(".build/checkouts")
        }

        let packageProjects = try await loadPackageProjects(
            paths: packagePaths,
            packageSettings: packageSettings,
            disableSandbox: disableSandbox
        )

        let projects = loadedWorkspace.projects.merging(
            packageProjects.projects,
            uniquingKeysWith: { _, newValue in newValue }
        )

        return LoadedWorkspace(
            path: loadedWorkspace.path,
            workspace: loadedWorkspace.workspace,
            projects: projects
        )
    }

    // MARK: - Private

    private func loadPackageProjects(
        paths: [AbsolutePath],
        packageSettings: TuistCore.PackageSettings?,
        disableSandbox: Bool
    ) async throws -> LoadedProjects {
        guard let packageSettings else { return LoadedProjects(projects: [:]) }
        var cache = [AbsolutePath: ProjectDescription.Project]()

        var paths = Set(paths)
        while !paths.isEmpty {
            paths.subtract(cache.keys)
            let projects = try await Array(paths).concurrentCompactMap {
                let packageInfo = try await manifestLoader.loadPackage(at: $0, disableSandbox: disableSandbox)
                return try await packageInfoMapper.map(
                    packageInfo: packageInfo,
                    path: $0,
                    packageType: .local,
                    packageSettings: packageSettings,
                    packageModuleAliases: [:]
                )
            }
            var newDependenciesPaths = Set<AbsolutePath>()
            for (path, project) in zip(paths, projects) {
                cache[path] = project
                await newDependenciesPaths.formUnion(try dependencyPaths(for: project, path: path))
            }
            paths = newDependenciesPaths
        }
        return LoadedProjects(projects: cache)
    }

    private func loadProjects(paths: [AbsolutePath], disableSandbox: Bool) async throws -> LoadedProjects {
        var cache = [AbsolutePath: ProjectDescription.Project]()

        var paths = Set(paths)
        while !paths.isEmpty {
            paths.subtract(cache.keys)
            let projects = try await Array(paths).concurrentMap {
                try await manifestLoader.loadProject(at: $0, disableSandbox: disableSandbox)
            }
            var newDependenciesPaths = Set<AbsolutePath>()
            for (path, project) in zip(paths, projects) {
                cache[path] = project
                await newDependenciesPaths.formUnion(try dependencyPaths(for: project, path: path))
            }
            paths = newDependenciesPaths
        }
        return LoadedProjects(projects: cache)
    }

    private func dependencyPaths(for project: ProjectDescription.Project, path: AbsolutePath) async throws -> [AbsolutePath] {
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: rootDirectory
        )
        let paths: [AbsolutePath] = try project.targets.flatMap {
            try $0.dependencies.compactMap {
                switch $0 {
                case let .project(target: _, path: projectPath, _, _):
                    return try generatorPaths.resolve(path: projectPath)
                default:
                    return nil
                }
            }
        }

        return paths.uniqued()
    }
}
