import Foundation
import TSCBasic
import TuistSupport

public struct CoreDataModel: Equatable {
    // MARK: - Attributes

    public let path: AbsolutePath
    public let versions: [AbsolutePath]
    public let currentVersion: String

    // MARK: - Init

    public init(path: AbsolutePath,
                versions: [AbsolutePath],
                currentVersion: String)
    {
        self.path = path
        self.versions = versions
        self.currentVersion = currentVersion
    }
}
