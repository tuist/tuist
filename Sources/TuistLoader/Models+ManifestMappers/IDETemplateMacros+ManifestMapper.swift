import Foundation
import ProjectDescription
import TuistGraph

extension IDETemplateMacros {
    static func from(
        manifest: ProjectDescription.FileHeaderTemplate,
        generatorPaths: GeneratorPaths
    ) throws -> IDETemplateMacros {
        switch manifest {
        case let .file(path):
            let templatePath = try generatorPaths.resolve(path: path)
            let templateContent = try String(contentsOf: templatePath.asURL)
            return IDETemplateMacros(fileHeader: templateContent)
        case let .string(templateContent):
            return IDETemplateMacros(fileHeader: templateContent)
        }
    }
}
