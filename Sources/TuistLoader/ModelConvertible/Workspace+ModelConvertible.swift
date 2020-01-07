import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Workspace: ModelConvertible {
    init(manifest: ProjectDescription.Workspace, generatorPaths: GeneratorPaths) throws {
        func globProjects(_ path: Path) throws -> [AbsolutePath] {
            let resolvedPath = try generatorPaths.resolve(path: path)
            let projects = FileHandler.shared.glob(AbsolutePath("/"), glob: String(resolvedPath.pathString.dropFirst()))
                .lazy
                .filter(FileHandler.shared.isFolder)
            return Array(projects)
        }

        let additionalFiles = try manifest.additionalFiles.compactMap {
            try TuistCore.FileElements(manifest: $0, generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistCore.Scheme(manifest: $0, generatorPaths: generatorPaths) }

        self.init(path: generatorPaths.manifestDirectory,
                  name: manifest.name,
                  projects: try manifest.projects.flatMap(globProjects),
                  schemes: schemes,
                  additionalFiles: additionalFiles)
    }
}
