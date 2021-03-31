import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// A component responsible for converting Manifests (`ProjectDescription`) to Models (`TuistCore`)
public protocol ManifestModelConverting {
    func convert(manifest: ProjectDescription.Workspace, path: AbsolutePath) throws -> TuistGraph.Workspace
    func convert(
        manifest: ProjectDescription.Project,
        path: AbsolutePath,
        plugins: Plugins
    ) throws -> TuistGraph.Project
}

public final class ManifestModelConverter: ManifestModelConverting {
    private let manifestLoader: ManifestLoading

    public convenience init() {
        self.init(
            manifestLoader: ManifestLoader()
        )
    }

    public init(manifestLoader: ManifestLoading) {
        self.manifestLoader = manifestLoader
    }

    public func convert(
        manifest: ProjectDescription.Project,
        path: AbsolutePath
    ) throws -> TuistGraph.Project {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        return try TuistGraph.Project.from(manifest: manifest, generatorPaths: generatorPaths)
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
}
