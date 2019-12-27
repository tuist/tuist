import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.CoreDataModel: ModelConvertible {
    init(manifest: ProjectDescription.CoreDataModel, generatorPaths: GeneratorPaths) throws {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        if !FileHandler.shared.exists(modelPath) {
            throw GeneratorModelLoaderError.missingFile(modelPath)
        }
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        self.init(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}
