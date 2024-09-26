import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.CoreDataModel {
    /// Maps a ProjectDescription.CoreDataModel instance into a XcodeGraph.CoreDataModel instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of Core Data model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CoreDataModel, generatorPaths: GeneratorPaths) async throws -> XcodeGraph
        .CoreDataModel
    {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")

        let currentVersion: String = try await {
            if let hardcodedVersion = manifest.currentVersion {
                return hardcodedVersion
            } else if try await CoreDataVersionExtractor.isVersioned(at: modelPath) {
                return try CoreDataVersionExtractor.version(fromVersionFileAtPath: modelPath)
            } else {
                return modelPath.basenameWithoutExt
            }
        }()

        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension XcodeGraph.CoreDataModel {
    /// Maps a `.xcdatamodeld` package into a XcodeGraph.CoreDataModel instance.
    /// - Parameters:
    ///   - path: The path for a `.xcdatamodeld` package.
    static func from(path modelPath: AbsolutePath) async throws -> XcodeGraph.CoreDataModel {
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion: String = try await {
            if try await CoreDataVersionExtractor.isVersioned(at: modelPath) {
                return try CoreDataVersionExtractor.version(fromVersionFileAtPath: modelPath)
            } else {
                return (versions.count == 1 ? versions[0] : modelPath).basenameWithoutExt
            }
        }()
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}
