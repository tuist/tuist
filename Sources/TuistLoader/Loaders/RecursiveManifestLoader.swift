import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport

/// A component that can load a manifest and all its (transitive) manifest dependencies
public protocol RecursiveManifestLoading {
    func loadWorkspace(
        at path: AbsolutePath,
        packageSettings: TuistGraph.PackageSettings?
    ) throws -> LoadedWorkspace
}

public struct LoadedProjects {
    public var projects: [AbsolutePath: ProjectDescription.Project]
    public var packageProducts: [String: [TuistGraph.TargetDependency]]
}

public struct LoadedWorkspace {
    public var path: AbsolutePath
    public var workspace: ProjectDescription.Workspace
    public var projects: [AbsolutePath: ProjectDescription.Project]
    public let packageProducts: [String: [TuistGraph.TargetDependency]]
}

enum ManifestPath: Hashable {
    case package(AbsolutePath)
    case project(AbsolutePath)

    var path: AbsolutePath {
        switch self {
        case let .project(path), let .package(path):
            return path
        }
    }
}

public class RecursiveManifestLoader: RecursiveManifestLoading {
    private let manifestLoader: ManifestLoading
    private let fileHandler: FileHandling
    private let packageInfoMapper: PackageInfoMapping

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileHandler: FileHandling = FileHandler.shared,
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper()
    ) {
        self.manifestLoader = manifestLoader
        self.fileHandler = fileHandler
        self.packageInfoMapper = packageInfoMapper
    }

    public func loadWorkspace(
        at path: AbsolutePath,
        packageSettings: TuistGraph.PackageSettings?
    ) throws -> LoadedWorkspace {
        let loadedWorkspace: ProjectDescription.Workspace?
        do {
            loadedWorkspace = try manifestLoader.loadWorkspace(at: path)
        } catch ManifestLoaderError.manifestNotFound {
            loadedWorkspace = nil
        }

        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let projectSearchPaths = (loadedWorkspace?.projects ?? ["."])
        let manifestPaths: [ManifestPath] = try projectSearchPaths.map {
            try generatorPaths.resolve(path: $0)
        }.flatMap {
            fileHandler.glob($0, glob: "")
        }.filter {
            fileHandler.isFolder($0) && $0.basename != Constants.tuistDirectoryName && !$0.pathString.contains(".build/checkouts")
        }.compactMap {
            let manifests = manifestLoader.manifests(at: $0)
            if manifests.contains(.project) {
                return .project($0)
            } else if manifests.contains(.package), !manifests.contains(.workspace) {
                return .package($0)
            } else {
                return nil
            }
        }

        let projects = try loadProjects(
            paths: manifestPaths,
            packageSettings: packageSettings
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
            projects: projects.projects,
            packageProducts: projects.packageProducts
        )
    }

    // MARK: - Private

    private func loadProjects(
        paths: [ManifestPath],
        packageSettings: TuistGraph.PackageSettings?
    ) throws -> LoadedProjects {
        var cache = [AbsolutePath: ProjectDescription.Project]()
        var packageProducts: [String: [TuistGraph.TargetDependency]] = [:]

        var paths = Set(paths)
        while !paths.isEmpty {
            paths = paths.filter {
                !cache.keys.contains($0.path)
            }
            var newDependenciesPaths = Set<ManifestPath>()
            let projects = try Array(paths).compactMap(context: ExecutionContext.concurrent) { manifestPath in
                switch manifestPath {
                case let .project(path):
                    return try manifestLoader.loadProject(at: path)
                case let .package(path):
                    guard let packageSettings else { return nil }
                    let packageInfo = try manifestLoader.loadPackage(at: path)
                    newDependenciesPaths.formUnion(
                        try packageInfo.dependencies.map {
                            switch $0 {
                            case let .local(path: localPackagePath):
                                return try .package(AbsolutePath(validating: localPackagePath))
                            }
                        }
                    )

                    let packageProject = try packageInfoMapper.map(
                        packageInfo: packageInfo,
                        path: path,
                        packageType: .local,
                        packageSettings: packageSettings,
                        packageToProject: [:]
                    )

                    for product in packageInfo.products {
                        packageProducts[product.name] = product.targets.map { target in
                            TuistGraph.TargetDependency.project(
                                target: target,
                                path: path,
                                condition: nil
                            )
                        }
                    }

                    return packageProject
                }
            }

            for (manifestPath, project) in zip(paths, projects) {
                cache[manifestPath.path] = project
                newDependenciesPaths.formUnion(try dependencyPaths(for: project, path: manifestPath.path))
            }
            paths = newDependenciesPaths
        }
        return LoadedProjects(
            projects: cache,
            packageProducts: packageProducts
        )
    }

    private func dependencyPaths(for project: ProjectDescription.Project, path: AbsolutePath) throws -> [ManifestPath] {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let paths: [ManifestPath] = try project.targets.flatMap {
            try $0.dependencies.compactMap {
                switch $0 {
                case let .project(target: _, path: projectPath, _):
                    return .project(try generatorPaths.resolve(path: projectPath))
                case let .xcodePackage(product: _, source: source, condition: _):
                    switch source {
                    case .external:
                        return nil
                    case let .local(packagePath):
                        return .package(try generatorPaths.resolve(path: packagePath))
                    }
                default:
                    return nil
                }
            }
        }

        return paths.uniqued()
    }
}
