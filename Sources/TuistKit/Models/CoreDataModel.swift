import Basic
import Foundation
import TuistCore

class CoreDataModel: Equatable, GraphJSONInitiatable {

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

    required init(json: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws {
        let pathString: String = try json.get("path")
        path = projectPath.appending(RelativePath(pathString))
        if !fileHandler.exists(path) {
            throw GraphLoadingError.missingFile(path)
        }
        currentVersion = try json.get("current_version")
        versions = path.glob("*.xcdatamodel")
    }

    // MARK: - Equatable

    static func == (lhs: CoreDataModel, rhs: CoreDataModel) -> Bool {
        return lhs.path == rhs.path &&
            lhs.currentVersion == rhs.currentVersion &&
            lhs.versions == rhs.versions
    }
}
