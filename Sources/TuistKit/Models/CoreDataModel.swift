import Basic
import Foundation
import TuistCore

class CoreDataModel: Equatable {
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

    // MARK: - Equatable

    static func == (lhs: CoreDataModel, rhs: CoreDataModel) -> Bool {
        return lhs.path == rhs.path &&
            lhs.currentVersion == rhs.currentVersion &&
            lhs.versions == rhs.versions
    }
}
