import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Workspace {
    /// Maps a ProjectDescription.Workspace instance into a TuistGraph.Workspace model.
    /// - Parameters:
    ///   - manifest: Manifest representation of workspace.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Workspace,
        path: AbsolutePath,
        generatorPaths: GeneratorPaths,
        manifestLoader: ManifestLoading
    ) throws -> TuistGraph.Workspace {
        func globProjects(_ path: Path) throws -> [AbsolutePath] {
            let resolvedPath = try generatorPaths.resolve(path: path)
            let projects = FileHandler.shared.glob(AbsolutePath.root, glob: String(resolvedPath.pathString.dropFirst()))
                .lazy
                .filter(FileHandler.shared.isFolder)
                .filter {
                    manifestLoader.manifests(at: $0).contains(.project)
                }

            if projects.isEmpty {
                // FIXME: This should be done in a linter.
                // Before we can do that we have to change the linters to run with the TuistCore models and not the ProjectDescription ones.
                logger.warning("No projects found at: \(path.pathString)")
            }

            return Array(projects)
        }

        let additionalFiles = try manifest.additionalFiles.flatMap {
            try TuistGraph.FileElement.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistGraph.Scheme.from(manifest: $0, generatorPaths: generatorPaths) }

        let generationOptions: GenerationOptions = try .from(manifest: manifest.generationOptions, generatorPaths: generatorPaths)

        let ideTemplateMacros = try manifest.fileHeaderTemplate
            .map { try IDETemplateMacros.from(manifest: $0, generatorPaths: generatorPaths) }

        return TuistGraph.Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "\(manifest.name).xcworkspace"),
            name: manifest.name,
            projects: try manifest.projects.flatMap(globProjects),
            schemes: schemes,
            generationOptions: generationOptions,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles
        )
    }
}
