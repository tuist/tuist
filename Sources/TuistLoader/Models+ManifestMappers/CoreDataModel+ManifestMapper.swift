import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CoreDataModel {
    /// Maps a ProjectDescription.CoreDataModel instance into a TuistGraph.CoreDataModel instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of Core Data model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CoreDataModel, generatorPaths: GeneratorPaths) throws -> TuistGraph.CoreDataModel {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")

        let currentVersion: String = try {
            if let hardcodedVersion = manifest.currentVersion {
                return hardcodedVersion
            } else if CoreDataVersionExtractor.isVersioned(at: modelPath) {
                return try CoreDataVersionExtractor.version(fromVersionFileAtPath: modelPath)
            } else {
                return modelPath.url.lastPathComponent.dropSuffix(".xcdatamodeld")
            }
        }()

        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}
