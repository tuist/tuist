import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

/// A component responsible for converting Manifests (`ProjectDescription`) to Models (`TuistCore`)
public protocol ManifestModelConverting {
    func convert(manifest: ProjectDescription.Workspace, path: AbsolutePath) throws -> TuistGraph.Workspace
    func convert(
        manifest: ProjectDescription.Project,
        path: AbsolutePath,
        plugins: Plugins,
        externalDependencies: [TuistGraph.Platform: [String: [TuistGraph.TargetDependency]]],
        isExternal: Bool
    ) throws -> TuistGraph.Project
    func convert(manifest: TuistCore.DependenciesGraph, path: AbsolutePath) throws -> TuistGraph.DependenciesGraph
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
        externalDependencies: [TuistGraph.Platform: [String: [TuistGraph.TargetDependency]]],
        isExternal: Bool
    ) throws -> TuistGraph.Project {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        return try TuistGraph.Project.from(
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
    ) throws -> TuistGraph.Workspace {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let workspace = try TuistGraph.Workspace.from(
            manifest: manifest,
            path: path,
            generatorPaths: generatorPaths,
            manifestLoader: manifestLoader
        )
        return workspace
    }

    public func convert(
        manifest: TuistCore.DependenciesGraph,
        path: AbsolutePath
    ) throws -> TuistGraph.DependenciesGraph {
        var externalDependencies: [TuistGraph.Platform: [String: [TuistGraph.TargetDependency]]] = .init()

        try manifest.externalDependencies.forEach { platform, targets in
            let targetToDependencies = try targets.mapValues { targetDependencies in
                try targetDependencies.flatMap { targetDependencyManifest in
                    try TuistGraph.TargetDependency.from(
                        manifest: targetDependencyManifest,
                        generatorPaths: GeneratorPaths(manifestDirectory: path),
                        externalDependencies: [:], // externalDependencies manifest can't contain other external dependencies,
                        platform: TuistGraph.Platform.from(manifest: platform)
                    )
                }
            }
            externalDependencies[try TuistGraph.Platform.from(manifest: platform)] = targetToDependencies
        }

        let externalProjects = try [AbsolutePath: TuistGraph.Project](
            uniqueKeysWithValues: manifest.externalProjects
                .map { project in
                    let projectPath = try AbsolutePath(validating: project.key.pathString)
                    var project = try convert(
                        manifest: project.value,
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
