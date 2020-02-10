import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.CoreDataModel {
    static func from(manifest: ProjectDescription.CoreDataModel,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.CoreDataModel {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}
