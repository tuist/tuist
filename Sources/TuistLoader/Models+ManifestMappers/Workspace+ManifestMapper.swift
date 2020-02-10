import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Workspace {
    static func from(manifest: ProjectDescription.Workspace,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths,
                     manifestLoader: ManifestLoading) throws -> TuistCore.Workspace {
        func globProjects(_ path: Path) throws -> [AbsolutePath] {
            let resolvedPath = try generatorPaths.resolve(path: path)
            let projects = FileHandler.shared.glob(AbsolutePath.root, glob: String(resolvedPath.pathString.dropFirst()))
                .lazy
                .filter(FileHandler.shared.isFolder)
                .filter {
                    manifestLoader.manifests(at: $0).contains(.project)
                }

            if projects.isEmpty {
                Printer.shared.print(warning: "No projects found at: \(path.pathString)")
            }

            return Array(projects)
        }

        let additionalFiles = try manifest.additionalFiles.flatMap {
            try TuistCore.FileElement.from(manifest: $0,
                                           path: path,
                                           generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistCore.Scheme.from(manifest: $0, workspacePath: path, generatorPaths: generatorPaths) }

        return TuistCore.Workspace(path: path,
                                   name: manifest.name,
                                   projects: try manifest.projects.flatMap(globProjects),
                                   schemes: schemes,
                                   additionalFiles: additionalFiles)
    }
}
