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
        isExternal: Bool
    ) async throws -> XcodeGraph.Project
    func convert(manifest: TuistLoader.DependenciesGraph, path: AbsolutePath) async throws -> XcodeGraph.DependenciesGraph
}

public final class ManifestModelConverter: ManifestModelConverting {
    private let manifestLoader: ManifestLoading
    private let resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating

    public convenience init() {
        self.init(
            manifestLoader: ManifestLoader()
        )
    }

    public convenience init(
        manifestLoader: ManifestLoading
    ) {
        self.init(
            manifestLoader: manifestLoader,
            resourceSynthesizerPathLocator: ResourceSynthesizerPathLocator()
        )
    }

    init(
        manifestLoader: ManifestLoading,
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating = ResourceSynthesizerPathLocator()
    ) {
        self.manifestLoader = manifestLoader
        self.resourceSynthesizerPathLocator = resourceSynthesizerPathLocator
    }

    public func convert(
        manifest: ProjectDescription.Project,
        path: AbsolutePath,
        plugins: Plugins,
        externalDependencies: [String: [XcodeGraph.TargetDependency]],
        isExternal: Bool
    ) async throws -> XcodeGraph.Project {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        return try await XcodeGraph.Project.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            plugins: plugins,
            externalDependencies: externalDependencies,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator,
            isExternal: isExternal
        )
    }

    public func convert(
        manifest: ProjectDescription.Workspace,
        path: AbsolutePath
    ) async throws -> XcodeGraph.Workspace {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let workspace = try await XcodeGraph.Workspace.from(
            manifest: manifest,
            path: path,
            generatorPaths: generatorPaths,
            manifestLoader: manifestLoader
        )
        return workspace
    }

    public func convert(
        manifest: TuistLoader.DependenciesGraph,
        path: AbsolutePath
    ) async throws -> XcodeGraph.DependenciesGraph {
        let externalDependencies: [String: [XcodeGraph.TargetDependency]] = try manifest.externalDependencies
            .mapValues { targetDependencies in
                try targetDependencies.flatMap { targetDependencyManifest in
                    try XcodeGraph.TargetDependency.from(
                        manifest: targetDependencyManifest,
                        generatorPaths: GeneratorPaths(manifestDirectory: path),
                        externalDependencies: [:] // externalDependencies manifest can't contain other external dependencies,
                    )
                }
            }

        let externalProjects = try await [AbsolutePath: XcodeGraph.Project](
            uniqueKeysWithValues: manifest.externalProjects
                .concurrentMap { path, project in
                    let projectPath = try AbsolutePath(validating: path.pathString)
                    var project = try await self.convert(
                        manifest: project,
                        path: projectPath,
                        plugins: .none,
                        externalDependencies: externalDependencies,
                        isExternal: true
                    )
                    // Disable all lastUpgradeCheck related warnings on projects generated from dependencies
                    project.lastUpgradeCheck = Version(99, 9, 9)
                    return (projectPath, project)
                }
        )

        return .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }
}
