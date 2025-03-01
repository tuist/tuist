import FileSystem
import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

/// A component responsible for converting Manifests (`ProjectDescription`) to Models (`TuistCore`)
public protocol ManifestModelConverting {
    func convert(manifest: ProjectDescription.Workspace, path: AbsolutePath) async throws -> XcodeGraph.Workspace
    func convert(
        manifest: ProjectDescription.Project,
        path: AbsolutePath,
        plugins: Plugins,
        externalDependencies: [String: [XcodeGraph.TargetDependency]],
        type: XcodeGraph.ProjectType
    ) async throws -> XcodeGraph.Project
    func convert(dependenciesGraph: TuistLoader.DependenciesGraph, path: AbsolutePath) async throws -> XcodeGraph
        .DependenciesGraph
}

public final class ManifestModelConverter: ManifestModelConverting {
    private let manifestLoader: ManifestLoading
    private let resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    public convenience init() {
        self.init(
            manifestLoader: ManifestLoader(),
            rootDirectoryLocator: RootDirectoryLocator()
        )
    }

    public convenience init(
        manifestLoader: ManifestLoading
    ) {
        self.init(
            manifestLoader: manifestLoader,
            resourceSynthesizerPathLocator: ResourceSynthesizerPathLocator(),
            rootDirectoryLocator: RootDirectoryLocator()
        )
    }

    init(
        manifestLoader: ManifestLoading,
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating = ResourceSynthesizerPathLocator(),
        rootDirectoryLocator: RootDirectoryLocating,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.manifestLoader = manifestLoader
        self.resourceSynthesizerPathLocator = resourceSynthesizerPathLocator
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    public func convert(
        manifest: ProjectDescription.Project,
        path: AbsolutePath,
        plugins: Plugins,
        externalDependencies: [String: [XcodeGraph.TargetDependency]],
        type: XcodeGraph.ProjectType
    ) async throws -> XcodeGraph.Project {
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: rootDirectory
        )
        return try await XcodeGraph.Project.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            plugins: plugins,
            externalDependencies: externalDependencies,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator,
            type: type,
            fileSystem: fileSystem
        )
    }

    public func convert(
        manifest: ProjectDescription.Workspace,
        path: AbsolutePath
    ) async throws -> XcodeGraph.Workspace {
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: rootDirectory
        )
        let workspace = try await XcodeGraph.Workspace.from(
            manifest: manifest,
            path: path,
            generatorPaths: generatorPaths,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem
        )
        return workspace
    }

    public func convert(
        dependenciesGraph: TuistLoader.DependenciesGraph,
        path: AbsolutePath
    ) async throws -> XcodeGraph.DependenciesGraph {
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: path)
        let externalDependencies: [String: [XcodeGraph.TargetDependency]] = try dependenciesGraph.externalDependencies
            .mapValues { targetDependencies in
                try targetDependencies.flatMap { targetDependencyManifest in
                    try XcodeGraph.TargetDependency.from(
                        manifest: targetDependencyManifest,
                        generatorPaths: GeneratorPaths(
                            manifestDirectory: path,
                            rootDirectory: rootDirectory
                        ),
                        externalDependencies: [:] // externalDependencies manifest can't contain other external dependencies,
                    )
                }
            }

        let externalProjects = try await [AbsolutePath: XcodeGraph.Project](
            uniqueKeysWithValues: dependenciesGraph.externalProjects
                .concurrentMap { path, project in
                    let projectType: ProjectType = switch project.sourcePackageType {
                        case .remote:
                                .external(hash: project.hash)
                        case .local:
                                .local
                    }
                    let projectPath = try AbsolutePath(validating: path.pathString)
                    var project = try await self.convert(
                        manifest: project.manifest,
                        path: projectPath,
                        plugins: .none,
                        externalDependencies: externalDependencies,
                        type: projectType
                    )
                    // Disable all lastUpgradeCheck related warnings on projects generated from dependencies
                    project.lastUpgradeCheck = Version(99, 9, 9)
                    return (projectPath, project)
                }
        )

        return .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }
}
