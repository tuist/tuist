import Foundation
import TSCBasic

/// Represents a Core Data model
public struct CoreDataModel: Equatable, Codable {
    // MARK: - Attributes

    /// Relative path to the Core Data model.
    public let path: AbsolutePath

    /// Paths to the versions.
    public let versions: [AbsolutePath]

    /// Current version without the extension.
    public let currentVersion: String

    // MARK: - Init

    public init(
        path: AbsolutePath,
        versions: [AbsolutePath],
        currentVersion: String
    ) {
        self.path = path
        self.versions = versions
        self.currentVersion = currentVersion
    }
}
