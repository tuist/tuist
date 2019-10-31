import Basic
import Foundation
import TuistSupport

public class CoreDataModel: Equatable {
    // MARK: - Attributes

    public let path: AbsolutePath
    public let versions: [AbsolutePath]
    public let currentVersion: String

    // MARK: - Init

    public init(path: AbsolutePath,
                versions: [AbsolutePath],
                currentVersion: String) {
        self.path = path
        self.versions = versions
        self.currentVersion = currentVersion
    }

    // MARK: - Equatable

    public static func == (lhs: CoreDataModel, rhs: CoreDataModel) -> Bool {
        return lhs.path == rhs.path &&
            lhs.currentVersion == rhs.currentVersion &&
            lhs.versions == rhs.versions
    }
}
