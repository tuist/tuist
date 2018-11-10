import Basic
import Foundation
import TuistCore

class CoreDataModel: Equatable, GraphInitiatable {
    // MARK: - Attributes

    let path: AbsolutePath
    let versions: [AbsolutePath]
    let currentVersion: String

    // MARK: - Init

    init(path: AbsolutePath,
         versions: [AbsolutePath],
         currentVersion: String) {
        self.path = path
        self.versions = versions
        self.currentVersion = currentVersion
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws {
        let pathString: String = try dictionary.get("path")
        path = projectPath.appending(RelativePath(pathString))
        if !fileHandler.exists(path) {
            throw GraphLoadingError.missingFile(path)
        }
        currentVersion = try dictionary.get("current_version")
        versions = path.glob("*.xcdatamodel")
    }

    // MARK: - Equatable

    static func == (lhs: CoreDataModel, rhs: CoreDataModel) -> Bool {
        return lhs.path == rhs.path &&
            lhs.currentVersion == rhs.currentVersion &&
            lhs.versions == rhs.versions
    }
}
