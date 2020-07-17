import Foundation
import ProjectDescription
import TSCBasic
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

        var currentVersion: String!
        if let hardcodedVersion = manifest.currentVersion {
            currentVersion = hardcodedVersion
        } else {
            currentVersion = try CoreDataVersionExtractor.version(fromVersionFileAtPath: modelPath)
        }
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

private final class CoreDataVersionExtractor {

    static func version(fromVersionFileAtPath filePath: AbsolutePath) throws -> String {
        let url = URL(fileURLWithPath: filePath.pathString + "/.xccurrentversion")
        do {
            let data = try Data(contentsOf: url)
            let decoder = PropertyListDecoder()
            let dict = try decoder.decode([String: String].self, from: data)
            guard
                let currentVersionName = dict["_XCCurrentVersionName"],
                let versionNumberString = currentVersionName.split(separator: ".").first
                else {
                    throw VersionExtractorError.couldNotExtractVersionFrom(filePath)
            }
            return String(versionNumberString)
        } catch {
            throw VersionExtractorError.couldNotReadCurrentVersion(filePath)
        }
    }

    enum VersionExtractorError: FatalError, Equatable {
        /// Thrown when the version could not be extracted from plist
        case couldNotExtractVersionFrom(AbsolutePath)

        /// Thrown when the xccurrentversion can't be read.
        case couldNotReadCurrentVersion(AbsolutePath)

        var type: ErrorType {
            switch self {
            case .couldNotExtractVersionFrom: return .abort
            case .couldNotReadCurrentVersion: return .abort
            }
        }

        var description: String {
            switch self {
            case let .couldNotExtractVersionFrom(path):
                return "Couldn't locate current version in .xccurrentversion from path \(path.pathString). Try setting the current version manually or check if the current version is set it in your project."
            case let .couldNotReadCurrentVersion(path):
                return "Couldn't read the xccurrentversion from path \(path.pathString). Try setting the current version manually or check if the current version is set it in your project."
            }
        }
    }
}
