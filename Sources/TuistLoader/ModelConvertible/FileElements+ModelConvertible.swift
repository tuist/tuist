import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.FileElements: ModelConvertible {
    init(manifest: ProjectDescription.FileElement, generatorPaths: GeneratorPaths) throws {
        switch manifest {
        case let .glob(pattern: pattern):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            let paths = FileHandler.shared.glob(AbsolutePath("/"), glob: String(resolvedPath.pathString.dropFirst()))
            self = FileElements.files(paths)
        case let .folderReference(path: folderReferencePath):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            self = FileElements.folderReferences([resolvedPath])
        }
    }
}
