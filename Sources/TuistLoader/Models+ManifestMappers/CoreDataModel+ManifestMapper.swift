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
    static func from(manifest: ProjectDescription.CoreDataModel, generatorPaths: GeneratorPaths) throws -> TuistGraph
        .CoreDataModel
    {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")

        let currentVersion: String = try {
            if let hardcodedVersion = manifest.currentVersion {
                return hardcodedVersion
            } else if CoreDataVersionExtractor.isVersioned(at: modelPath) {
                return try CoreDataVersionExtractor.version(fromVersionFileAtPath: modelPath)
            } else {
                return modelPath.basenameWithoutExt
            }
        }()

        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension TuistGraph.CoreDataModel {
    /// Maps a `.xcdatamodeld` package into a TuistGraph.CoreDataModel instance.
    /// - Parameters:
    ///   - path: The path for a `.xcdatamodeld` package.
    static func from(path modelPath: AbsolutePath) throws -> TuistGraph.CoreDataModel {
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion: String = try {
            if CoreDataVersionExtractor.isVersioned(at: modelPath) {
                return try CoreDataVersionExtractor.version(fromVersionFileAtPath: modelPath)
            } else {
                return (versions.count == 1 ? versions[0] : modelPath).basenameWithoutExt
            }
        }()
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}
