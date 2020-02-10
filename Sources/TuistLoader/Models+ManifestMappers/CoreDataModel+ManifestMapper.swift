import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.CoreDataModel {
    /// Maps a ProjectDescription.CoreDataModel instance into a TuistCore.CoreDataModel instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of Core Data model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CoreDataModel, generatorPaths: GeneratorPaths) throws -> TuistCore.CoreDataModel {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}
